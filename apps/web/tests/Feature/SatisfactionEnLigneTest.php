<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

/**
 * SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8). Ces essais prouvent : la mère publie (signée) un lien et son modèle ; la page
 * publique rend CE modèle, sans lien vers le logiciel ni ressource externe ; jeton inconnu, expiré, révoqué ou mal formé reçoivent LA MÊME réponse ; une
 * enveloppe chiffrée dans le navigateur (le MÊME script, exécuté par Node) est stockée sans qu'aucune réponse n'y soit lisible ; la mère la relève, la
 * déchiffre avec sa clé privée (que le relais n'a jamais vue) et l'acquitte, ce qui l'efface ; débit, plafond et formes sont refusés en les nommant.
 */
class SatisfactionEnLigneTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-de-la-mere-pour-les-essais-satisfaction';

    private const JETON = 'abcdefghijkmnpqrstuvwxyz';

    private const KID = '0123456789abcdef';

    private const PK = 'hBpaTOYJH_KqkSmW7e89DKR8__hKLiqHY5urlL8wn0c';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'satisfaction.plafond_par_lien_et_jour' => 500]);
    }

    private function mere(string $chemin, array $corps, ?string $secret = null, ?string $signature = null)
    {
        $brut = json_encode($corps, JSON_UNESCAPED_UNICODE);
        $secret ??= self::SECRET;

        return $this->call('POST', $chemin, [], [], [], [
            'HTTP_X_MERE' => $secret,
            'HTTP_X_SIGNATURE' => $signature ?? 'sha256='.hash_hmac('sha256', $brut, $secret),
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
        ], $brut);
    }

    private function publication(array $plus = []): array
    {
        return array_replace([
            'jeton_hash' => hash('sha256', self::JETON),
            'ref' => 'JET-0001',
            'expire_le' => now('Africa/Porto-Novo')->addDays(30)->format('Y-m-d'),
            'clinique' => 'Clinique d\'essai',
            'titre' => 'Votre avis compte',
            'description' => 'Trois questions sur votre passage.',
            'champs' => [
                ['nom' => 'Q_ACCUEIL', 'libelle' => 'Qualité de l\'accueil (1 à 5)', 'type' => 'select', 'requis' => true, 'options' => ['1', '2', '3', '4', '5'], 'lignes' => 3],
                ['nom' => 'Q_RECO', 'libelle' => 'Recommanderiez-vous la clinique ?', 'type' => 'select', 'requis' => true, 'options' => ['Oui', 'Plutôt oui', 'Non'], 'lignes' => 3],
                ['nom' => 'Q_COM', 'libelle' => 'Un commentaire ?', 'type' => 'textarea', 'requis' => false, 'options' => [], 'lignes' => 2],
            ],
            'cle_publique' => self::PK,
            'kid' => self::KID,
        ], $plus);
    }

    private function enveloppeFactice(array $plus = []): array
    {
        $b64u = fn (string $b) => rtrim(strtr(base64_encode($b), '+/', '-_'), '=');

        return array_replace(['v' => 'sat1', 'kid' => self::KID, 'epk' => $b64u(random_bytes(32)), 'iv' => $b64u(random_bytes(12)), 'ct' => $b64u(random_bytes(256 + 16))], $plus);
    }

    private function deposer(array $enveloppe, string $jeton = self::JETON)
    {
        return $this->postJson('/satisfaction/'.$jeton.'/reponse', ['enveloppe' => $enveloppe]);
    }

    private function node(array $entree): array
    {
        $proc = proc_open(['node', base_path('tests/js/satisfaction.mjs')], [0 => ['pipe', 'r'], 1 => ['pipe', 'w'], 2 => ['pipe', 'w']], $tubes);
        fwrite($tubes[0], json_encode($entree));
        fclose($tubes[0]);
        $sortie = stream_get_contents($tubes[1]);
        proc_close($proc);

        return json_decode($sortie, true) ?? ['erreur' => 'sortie illisible : '.$sortie];
    }

    private function exigerNode(): void
    {
        if (trim((string) shell_exec('command -v node')) === '') {
            $this->markTestSkipped('Node absent : le chiffrement du navigateur n\'est pas mesurable ici.');
        }
    }

    // --- publication par la mère -------------------------------------------------------------------------------------------------------------------

    public function test_la_mere_publie_un_lien_signe_le_jeton_n_est_garde_que_hache(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk()->assertJson(['ok' => true, 'cree' => true]);
        $l = DB::table('satisfaction_liens')->first();
        $this->assertSame(hash('sha256', self::JETON), $l->jeton_hash);
        $this->assertStringNotContainsString(self::JETON, json_encode(DB::table('satisfaction_liens')->get()));
        // Republier (une question ajoutée au modèle) met à jour le même lien.
        $p = $this->publication();
        $p['champs'][] = ['nom' => 'Q_PROPRE', 'libelle' => 'Propreté des locaux (1 à 5)', 'type' => 'select', 'requis' => true, 'options' => ['1', '2', '3', '4', '5'], 'lignes' => 3];
        $this->mere('/mere/satisfaction/publier', $p)->assertOk()->assertJson(['cree' => false]);
        $this->assertDatabaseCount('satisfaction_liens', 1);
        $this->get('/satisfaction/'.self::JETON)->assertOk()->assertSee('Propreté des locaux (1 à 5)');
    }

    public function test_sans_secret_ou_signature_faux_rien_n_est_publie(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication(), 'faux')->assertStatus(403)->assertJson(['code' => 'mere_requise']);
        $this->mere('/mere/satisfaction/publier', $this->publication(), null, 'sha256=00')->assertStatus(401)->assertJson(['code' => 'signature_invalide']);
        foreach (['/mere/satisfaction/revoquer', '/mere/satisfaction/relever', '/mere/satisfaction/acquitter'] as $route) {
            $this->mere($route, [], 'faux')->assertStatus(403);
            $this->mere($route, [], null, 'sha256=00')->assertStatus(401);
        }
        $this->assertDatabaseCount('satisfaction_liens', 0);
    }

    public function test_une_publication_hors_schema_est_refusee_en_le_nommant(): void
    {
        $cas = [
            'champ inattendu' => $this->publication(['patient' => 'X']),
            'nom réservé au poste' => $this->publication(['champs' => [['nom' => '_repondant', 'libelle' => 'Votre nom', 'type' => 'textarea', 'requis' => true, 'options' => [], 'lignes' => 1]]]),
            'type inconnu' => $this->publication(['champs' => [['nom' => 'Q', 'libelle' => 'Q', 'type' => 'html', 'requis' => true, 'options' => [], 'lignes' => 1]]]),
            'liste sans choix' => $this->publication(['champs' => [['nom' => 'Q', 'libelle' => 'Q', 'type' => 'select', 'requis' => true, 'options' => [], 'lignes' => 1]]]),
            'clé publique' => $this->publication(['cle_publique' => 'courte']),
            'date' => $this->publication(['expire_le' => '2026-02-31']),
        ];
        foreach ($cas as $nom => $p) {
            $this->mere('/mere/satisfaction/publier', $p)->assertStatus(422)->assertJson(['code' => 'publication_invalide'], $nom);
        }
        $this->assertDatabaseCount('satisfaction_liens', 0);
    }

    // --- la page publique ----------------------------------------------------------------------------------------------------------------------------

    public function test_la_page_publique_rend_le_modele_sans_lien_vers_le_logiciel_ni_ressource_externe(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $r = $this->get('/satisfaction/'.self::JETON)->assertOk();
        $html = (string) $r->getContent();
        foreach (['Votre avis compte', 'Qualité de l&#039;accueil (1 à 5)', 'Recommanderiez-vous la clinique ?', 'Un commentaire ?', 'name="Q_COM"', 'ANONYME'] as $attendu) {
            $this->assertStringContainsString($attendu, $html);
        }
        // Aucun lien vers le panneau ou le logiciel, aucune ressource hors du relais, aucune présélection d'une note.
        $this->assertDoesNotMatchRegularExpression('/<a\s/i', $html);
        $this->assertStringNotContainsString('panneau', $html);
        $this->assertDoesNotMatchRegularExpression('#(src|href)="https?://(?!localhost)#', $html);
        $this->assertStringNotContainsString('selected', $html);
        $this->assertStringContainsString("default-src 'none'", (string) $r->headers->get('Content-Security-Policy'));
        $this->assertSame('no-referrer', $r->headers->get('Referrer-Policy'));
        $this->assertStringContainsString('no-store', (string) $r->headers->get('Cache-Control'));
        $this->assertNull($r->headers->get('Set-Cookie'));
        $this->getJson('/satisfaction/'.self::JETON.'/modele')->assertOk()->assertJsonPath('kid', self::KID)->assertJsonCount(3, 'champs');
    }

    public function test_jeton_inconnu_expire_revoque_ou_mal_forme_recoivent_la_meme_reponse(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $this->mere('/mere/satisfaction/publier', $this->publication(['jeton_hash' => hash('sha256', 'expireexpireexpireexpire'), 'ref' => 'JET-0002', 'expire_le' => now('Africa/Porto-Novo')->subDay()->format('Y-m-d')]))->assertOk();
        $this->mere('/mere/satisfaction/publier', $this->publication(['jeton_hash' => hash('sha256', 'revoquerevoquerevoquerev'), 'ref' => 'JET-0003']))->assertOk();
        $this->mere('/mere/satisfaction/revoquer', ['jeton_hash' => hash('sha256', 'revoquerevoquerevoquerev')])->assertOk();
        $pages = $modeles = $depots = [];
        foreach (['inconnuinconnuinconnuinc', 'expireexpireexpireexpire', 'revoquerevoquerevoquerev', 'mal%20forme', 'MAJUSCULESINTERDITES1234'] as $j) {
            $p = $this->get('/satisfaction/'.$j);
            $pages[] = $p->getStatusCode().'|'.$p->getContent();
            $m = $this->getJson('/satisfaction/'.$j.'/modele');
            $modeles[] = $m->getStatusCode().'|'.$m->getContent();
            $d = $this->deposer($this->enveloppeFactice(), $j);
            $depots[] = $d->getStatusCode().'|'.$d->getContent();
        }
        foreach ([$pages, $modeles, $depots] as $serie) {
            $this->assertCount(1, array_unique($serie), 'une seule réponse pour tous les jetons non valables');
            $this->assertStringStartsWith('404|', $serie[0]);
        }
        $this->assertStringNotContainsString('Votre avis compte', $pages[0]);
        $this->assertStringNotContainsString('Clinique d', $pages[0]);
        $this->assertDatabaseCount('satisfaction_enveloppes', 0);
    }

    // --- le dépôt ------------------------------------------------------------------------------------------------------------------------------------

    public function test_une_enveloppe_mal_formee_ou_d_une_cle_perimee_est_refusee(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $this->deposer(['reponses' => ['Q_ACCUEIL' => '5']])->assertStatus(422)->assertJson(['code' => 'enveloppe_invalide']);
        $this->deposer($this->enveloppeFactice(['v' => 'sat2']))->assertStatus(422);
        $this->deposer($this->enveloppeFactice(['ct' => 'AAAA']))->assertStatus(422);
        $this->deposer($this->enveloppeFactice(['clair' => 'x']))->assertStatus(422);
        $this->deposer($this->enveloppeFactice(['kid' => 'fedcba9876543210']))->assertStatus(409)->assertJson(['code' => 'cle_perimee']);
        $this->assertDatabaseCount('satisfaction_enveloppes', 0);
        $this->deposer($this->enveloppeFactice())->assertStatus(202);
        $this->assertDatabaseCount('satisfaction_enveloppes', 1);
    }

    public function test_le_plafond_par_lien_et_par_jour_est_tenu(): void
    {
        config(['satisfaction.plafond_par_lien_et_jour' => 2]);
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $this->deposer($this->enveloppeFactice())->assertStatus(202);
        $this->deposer($this->enveloppeFactice())->assertStatus(202);
        $this->deposer($this->enveloppeFactice())->assertStatus(429)->assertJson(['code' => 'plafond_atteint']);
        $this->assertDatabaseCount('satisfaction_enveloppes', 2);
    }

    public function test_le_debit_du_depot_est_limite_par_adresse(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $statuts = [];
        for ($i = 0; $i < 12; $i++) {
            $statuts[] = $this->deposer($this->enveloppeFactice())->getStatusCode();
        }
        $this->assertContains(429, $statuts, 'au-delà du débit permis par minute, le dépôt est refusé');
    }

    public function test_aucune_adresse_reseau_ni_heure_fine_n_est_stockee_avec_une_reponse(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $this->withServerVariables(['REMOTE_ADDR' => '203.0.113.77'])->deposer($this->enveloppeFactice())->assertStatus(202);
        $tout = json_encode(DB::table('satisfaction_enveloppes')->get());
        $this->assertStringNotContainsString('203.0.113.77', $tout);
        $this->assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2}$/', DB::table('satisfaction_enveloppes')->value('recue_le'));
    }

    // --- relève, déchiffrement par la mère, acquittement --------------------------------------------------------------------------------------------

    public function test_bout_en_bout_le_navigateur_chiffre_le_relais_stocke_la_mere_dechiffre_puis_acquitte(): void
    {
        $this->exigerNode();
        $paire = $this->node(['action' => 'paire'])['paire'];
        $this->mere('/mere/satisfaction/publier', $this->publication(['cle_publique' => $paire['publique'], 'kid' => $paire['kid']]))->assertOk();
        $pub = $this->getJson('/satisfaction/'.self::JETON.'/modele')->json();
        $reponses = ['Q_ACCUEIL' => '4', 'Q_RECO' => 'Plutôt oui', 'Q_COM' => 'Sentinelle-Commentaire-Opaque'];
        $env = $this->node(['action' => 'chiffrer', 'reponses' => $reponses, 'publication' => $pub])['enveloppe'] ?? null;
        $this->assertIsArray($env);
        unset($env['voie']);
        $this->deposer($env)->assertStatus(202);

        // Opacité : rien de lisible dans ce que le relais détient.
        $tout = json_encode([DB::table('satisfaction_enveloppes')->get(), DB::table('satisfaction_liens')->get(), DB::table('relais_audit')->get()]);
        $this->assertStringNotContainsString('Sentinelle', $tout);
        $this->assertStringNotContainsString('Plutôt oui', $tout);

        $releve = $this->mere('/mere/satisfaction/relever', [])->assertOk()->json();
        $this->assertCount(1, $releve['enveloppes']);
        $e = $releve['enveloppes'][0];
        $this->assertSame('JET-0001', $e['ref']);
        $this->assertSame($reponses, $this->node(['action' => 'dechiffrer', 'enveloppe' => $e['enveloppe'], 'paire' => $paire, 'jeton' => self::JETON])['reponses'] ?? null);

        $this->mere('/mere/satisfaction/acquitter', ['ids' => [$e['id']]])->assertOk()->assertJson(['acquittees' => 1]);
        $this->assertDatabaseCount('satisfaction_enveloppes', 0);
        $this->assertSame([], $this->mere('/mere/satisfaction/relever', [])->json('enveloppes'));
    }

    public function test_une_revocation_ferme_la_porte_sans_effacer_les_reponses_deja_deposees(): void
    {
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertOk();
        $this->deposer($this->enveloppeFactice())->assertStatus(202);
        $this->mere('/mere/satisfaction/revoquer', ['jeton_hash' => hash('sha256', self::JETON)])->assertOk();
        $this->get('/satisfaction/'.self::JETON)->assertStatus(404);
        $this->deposer($this->enveloppeFactice())->assertStatus(404);
        $this->assertCount(1, $this->mere('/mere/satisfaction/relever', [])->json('enveloppes'));
        $this->mere('/mere/satisfaction/publier', $this->publication())->assertStatus(409)->assertJson(['code' => 'lien_revoque']);
    }

    public function test_le_controleur_ne_contient_aucun_chiffrement_ni_cle(): void
    {
        foreach (['Http/Controllers/SatisfactionController.php', 'Relais/Satisfaction/Publication.php'] as $f) {
            $src = file_get_contents(app_path($f));
            $this->assertDoesNotMatchRegularExpression('/openssl_|sodium_|Crypt::|Crypto|encrypt\(|decrypt\(|AES|GCM/i', $src, $f);
        }
    }

    public function test_les_crochets_du_banc_sont_fermes_par_defaut(): void
    {
        $this->getJson('/banc/satisfaction/tout')->assertStatus(404);
        $this->postJson('/banc/satisfaction/vieillir', ['ref' => 'x'])->assertStatus(404);
    }
}
