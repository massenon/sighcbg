<?php

namespace Tests\Feature;

use App\Relais\Sms\Envoyeur;
use App\Relais\Sms\FileSms;
use App\Relais\Sms\Pilote;
use App\Relais\Sms\PiloteEchec;
use App\Relais\Sms\PiloteHttp;
use App\Relais\Sms\PiloteJournal;
use App\Relais\Sms\ResultatEnvoi;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

/**
 * ADR-0009 : les SMS par le relais. Ces tests prouvent : les barrières du dépôt (secret, signature, schéma fermé, taille), l'idempotence, le plafond
 * quotidien, l'envoi par la tâche planifiée et l'EFFACEMENT du numéro et du texte après envoi, les cinq tentatives au plus puis l'effacement sur échec,
 * un journal technique sans numéro ni texte, le suivi de statut, le pilote HTTP générique réglé par le .env seulement, et les crochets du banc fermés.
 *
 * Écrits le 16/11/2026, NON EXÉCUTÉS dans l'environnement de l'agent (pas de vendor/ : `composer install` y est proscrit). À lancer : `php artisan test --filter=SmsRelaisTest`.
 */
class SmsRelaisTest extends TestCase
{
    use RefreshDatabase;

    private const SECRET = 'secret-mere-essai-sms';

    private const NUMERO = '+22900000001';

    private const TEXTE = 'Bonjour, nous vous rappelons votre rendez-vous a la clinique le 18/11/2026 a 09h00.';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET, 'relais.banc' => false, 'relais.sms.plafond_jour' => 100, 'relais.sms.tentatives_max' => 5, 'relais.sms.pilote' => 'journal']);
    }

    private function signe(string $chemin, array $corps, ?string $secret = null, ?string $signature = null, ?string $brut = null)
    {
        $brut ??= json_encode($corps, JSON_UNESCAPED_UNICODE);
        $secret ??= self::SECRET;

        return $this->call('POST', $chemin, [], [], [], [
            'HTTP_X_MERE' => $secret,
            'HTTP_X_SIGNATURE' => $signature ?? 'sha256='.hash_hmac('sha256', $brut, $secret),
            'CONTENT_TYPE' => 'application/json',
            'HTTP_ACCEPT' => 'application/json',
        ], $brut);
    }

    private function deposer(string $id = 'sms-0000000001', string $numero = self::NUMERO, string $texte = self::TEXTE)
    {
        return $this->signe('/mere/sms', ['sms' => ['id' => $id, 'numero' => $numero, 'texte' => $texte]]);
    }

    private function auditSms(): string
    {
        return DB::table('relais_audit')->where('acteur', 'sms')->get()->toJson();
    }

    // --- dépôt ---------------------------------------------------------------------------------------------------------------------------------

    public function test_un_sms_signe_et_conforme_est_depose_en_attente(): void
    {
        $this->deposer()->assertOk()->assertJson(['ok' => true, 'rejeu' => false, 'sms' => ['id' => 'sms-0000000001', 'statut' => 'en_attente', 'tentatives' => 0]]);
        $l = DB::table('sms_sortants')->first();
        $this->assertSame(self::NUMERO, $l->numero);
        $this->assertSame(self::TEXTE, $l->texte);
        $this->assertSame(mb_strlen(self::TEXTE), (int) $l->longueur);
    }

    public function test_la_reponse_du_depot_ne_repete_ni_le_numero_ni_le_texte(): void
    {
        $c = (string) $this->deposer()->getContent();
        $this->assertStringNotContainsString('22900000001', $c);
        $this->assertStringNotContainsString('rendez-vous', $c);
    }

    public function test_un_depot_rejoue_rend_la_meme_ligne_sans_doublon(): void
    {
        $this->deposer()->assertOk();
        $this->deposer()->assertOk()->assertJson(['rejeu' => true]);
        $this->assertDatabaseCount('sms_sortants', 1);
    }

    public function test_sans_secret_ou_avec_un_faux_secret_le_depot_est_refuse(): void
    {
        $this->postJson('/mere/sms', ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => self::TEXTE]])->assertStatus(403)->assertJson(['code' => 'mere_requise']);
        $this->signe('/mere/sms', ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => self::TEXTE]], 'faux-secret')->assertStatus(403);
        $this->assertDatabaseCount('sms_sortants', 0);
    }

    public function test_une_signature_fausse_ou_un_corps_altere_sont_refuses(): void
    {
        $corps = ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => self::TEXTE]];
        $this->signe('/mere/sms', $corps, null, 'sha256='.str_repeat('0', 64))->assertStatus(401)->assertJson(['code' => 'signature_invalide']);
        $sig = 'sha256='.hash_hmac('sha256', json_encode($corps), self::SECRET);
        $altere = json_encode(['sms' => ['id' => 'sms-0000000001', 'numero' => '+22900000009', 'texte' => self::TEXTE]]);
        $this->signe('/mere/sms', [], null, $sig, $altere)->assertStatus(401);
        $this->assertDatabaseCount('sms_sortants', 0);
    }

    public function test_le_schema_est_ferme_et_les_refus_nomment_un_chemin_jamais_une_valeur(): void
    {
        $cas = [
            'champ en trop (occasion)' => ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => self::TEXTE, 'patient' => 'ZOUNON Kadidja']],
            'numéro local' => ['sms' => ['id' => 'sms-0000000001', 'numero' => '0100000001', 'texte' => self::TEXTE]],
            'texte vide' => ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => '']],
            'texte trop long' => ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => str_repeat('a', 321)]],
            'identifiant court' => ['sms' => ['id' => 'x', 'numero' => self::NUMERO, 'texte' => self::TEXTE]],
            'deux objets' => ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => self::TEXTE], 'autre' => 1],
            'caractère de contrôle' => ['sms' => ['id' => 'sms-0000000001', 'numero' => self::NUMERO, 'texte' => "a\x07b"]],
        ];
        foreach ($cas as $nom => $corps) {
            $r = $this->signe('/mere/sms', $corps);
            $r->assertStatus(422)->assertJson(['code' => 'sms_invalide']);
            $this->assertStringNotContainsString('Kadidja', (string) $r->getContent(), $nom);
            $this->assertStringNotContainsString('0100000001', (string) $r->getContent(), $nom);
        }
        $this->assertDatabaseCount('sms_sortants', 0);
    }

    public function test_un_corps_trop_gros_est_refuse_sans_etre_lu(): void
    {
        config(['relais.sms.octets_max' => 64]);
        $this->deposer()->assertStatus(413)->assertJson(['code' => 'corps_trop_gros']);
    }

    // --- plafond -------------------------------------------------------------------------------------------------------------------------------

    public function test_le_plafond_du_jour_refuse_le_depot_de_trop_puis_l_envoi_s_arrete_au_plafond(): void
    {
        config(['relais.sms.plafond_jour' => 2]);
        $this->deposer('sms-0000000001')->assertOk();
        $this->deposer('sms-0000000002')->assertOk();
        $this->deposer('sms-0000000003')->assertStatus(429)->assertJson(['code' => 'plafond_atteint']);
        Envoyeur::tourner(new PiloteJournal());
        $this->assertSame(2, FileSms::envoyesAujourdhui());
        // Les deux envoyés comptent toujours : un troisième dépôt reste refusé le même jour.
        $this->deposer('sms-0000000003')->assertStatus(429);
        // Un SMS en attente au-delà du plafond (plafond abaissé après dépôt) n'est pas envoyé.
        config(['relais.sms.plafond_jour' => 3]);
        $this->deposer('sms-0000000003')->assertOk();
        config(['relais.sms.plafond_jour' => 2]);
        $b = Envoyeur::tourner(new PiloteJournal());
        $this->assertSame(0, $b['envoyes']);
        $this->assertTrue($b['plafond_atteint']);
        $this->assertSame('en_attente', DB::table('sms_sortants')->where('uid', 'sms-0000000003')->value('statut'));
    }

    public function test_le_plafond_suit_le_jour_civil_de_porto_novo(): void
    {
        config(['relais.sms.plafond_jour' => 1]);
        $hier = FileSms::debutDuJour() - 3600000;
        DB::table('sms_sortants')->insert(['uid' => 'sms-hier-00001', 'longueur' => 10, 'statut' => 'envoye', 'tentatives' => 1, 'depose_le' => $hier, 'prochain_essai_le' => $hier, 'envoye_le' => $hier, 'efface_le' => $hier]);
        $this->deposer()->assertOk();
    }

    // --- envoi et effacement -------------------------------------------------------------------------------------------------------------------

    public function test_la_tache_planifiee_envoie_puis_efface_le_numero_et_le_texte(): void
    {
        $this->deposer()->assertOk();
        $this->assertSame(0, Artisan::call('relais:sms-envoyer'));
        $this->assertStringNotContainsString('22900000001', Artisan::output());
        $l = DB::table('sms_sortants')->first();
        $this->assertSame('envoye', $l->statut);
        $this->assertNull($l->numero);
        $this->assertNull($l->texte);
        $this->assertNotNull($l->envoye_le);
        $this->assertNotNull($l->efface_le);
        $this->assertSame(1, (int) $l->tentatives);
    }

    public function test_la_tache_est_inscrite_au_planificateur_chaque_minute(): void
    {
        // Les routes de console (routes/console.php) se chargent quand le noyau de console démarre : on le démarre avant de lire le planificateur.
        Artisan::call('schedule:list');
        $evenements = collect(app(\Illuminate\Console\Scheduling\Schedule::class)->events())->filter(fn ($e) => str_contains((string) $e->command, 'relais:sms-envoyer'));
        $this->assertCount(1, $evenements);
        $this->assertSame('* * * * *', $evenements->first()->expression);
    }

    public function test_cinq_tentatives_au_plus_puis_echec_et_effacement(): void
    {
        $this->deposer()->assertOk();
        $t = (int) (microtime(true) * 1000);
        for ($i = 1; $i <= 4; $i++) {
            $b = Envoyeur::tourner(new PiloteEchec(), $t);
            $this->assertSame(1, $b['echecs'], 'tentative '.$i);
            $l = DB::table('sms_sortants')->first();
            $this->assertSame('en_attente', $l->statut);
            $this->assertSame($i, (int) $l->tentatives);
            $this->assertSame('essai_echec', $l->derniere_erreur);
            $this->assertNotNull($l->numero, 'le numéro reste tant qu\'un essai suit');
            // Le délai entre deux tentatives est respecté : un tour immédiat n'essaie pas.
            $this->assertSame(0, Envoyeur::tourner(new PiloteEchec(), $t)['echecs']);
            $t = (int) $l->prochain_essai_le;
        }
        $b = Envoyeur::tourner(new PiloteEchec(), $t);
        $this->assertSame(1, $b['abandons']);
        $l = DB::table('sms_sortants')->first();
        $this->assertSame('echec', $l->statut);
        $this->assertSame(5, (int) $l->tentatives);
        $this->assertNull($l->numero);
        $this->assertNull($l->texte);
        $this->assertSame(0, Envoyeur::tourner(new PiloteEchec(), $t + 86400000)['echecs'], 'plus rien n\'est tenté après le cinquième échec');
    }

    public function test_un_reglage_au_dela_de_cinq_tentatives_est_ramene_a_cinq(): void
    {
        config(['relais.sms.tentatives_max' => 12]);
        $this->assertSame(5, FileSms::tentativesMax());
    }

    public function test_une_exception_du_pilote_compte_comme_un_echec_nomme(): void
    {
        $this->deposer()->assertOk();
        $pilote = new class implements Pilote {
            public function nom(): string
            {
                return 'casse';
            }

            public function envoyer(string $numero, string $texte): ResultatEnvoi
            {
                throw new \RuntimeException('réponse du fournisseur : '.$texte);
            }
        };
        Envoyeur::tourner($pilote);
        $this->assertSame('exception', DB::table('sms_sortants')->value('derniere_erreur'));
        $this->assertStringNotContainsString('rendez-vous', $this->auditSms());
    }

    public function test_le_journal_technique_ne_porte_ni_numero_ni_texte(): void
    {
        $this->deposer('sms-0000000001')->assertOk();
        $this->deposer('sms-0000000002', '+22900000002', 'Bonjour, la clinique vous souhaite une bonne fete.')->assertOk();
        $this->signe('/mere/sms', ['sms' => ['id' => 'sms-0000000003', 'numero' => '0100000003', 'texte' => 'x']])->assertStatus(422);
        Envoyeur::tourner(new PiloteEchec());
        Envoyeur::tourner(new PiloteJournal(), (int) (microtime(true) * 1000) + 3600000);
        $audit = $this->auditSms();
        $this->assertStringContainsString('sms_depose', $audit);
        $this->assertStringContainsString('sms_envoye', $audit);
        $this->assertStringContainsString('sms_echec', $audit);
        $this->assertStringContainsString('sms_refuse', $audit);
        foreach (['22900000001', '22900000002', '0100000003', 'rendez-vous', 'fete'] as $interdit) {
            $this->assertStringNotContainsString($interdit, $audit);
        }
    }

    public function test_les_lignes_terminees_sont_purgees_apres_la_conservation_jamais_celles_en_attente(): void
    {
        config(['relais.sms.conservation_jours' => 30]);
        $vieux = (int) (microtime(true) * 1000) - 31 * 86400000;
        DB::table('sms_sortants')->insert([
            ['uid' => 'sms-vieux-envoye', 'longueur' => 1, 'statut' => 'envoye', 'tentatives' => 1, 'depose_le' => $vieux, 'prochain_essai_le' => $vieux, 'envoye_le' => $vieux, 'efface_le' => $vieux, 'numero' => null, 'texte' => null],
            ['uid' => 'sms-vieux-attente', 'longueur' => 1, 'statut' => 'en_attente', 'tentatives' => 0, 'depose_le' => $vieux, 'prochain_essai_le' => PHP_INT_MAX, 'envoye_le' => null, 'efface_le' => null, 'numero' => self::NUMERO, 'texte' => 'x'],
        ]);
        $this->assertSame(1, Envoyeur::purger());
        $this->assertSame(['sms-vieux-attente'], DB::table('sms_sortants')->pluck('uid')->all());
    }

    // --- suivi et état -------------------------------------------------------------------------------------------------------------------------

    public function test_la_mere_suit_le_statut_sans_jamais_relire_le_numero_ni_le_texte(): void
    {
        $this->deposer('sms-0000000001')->assertOk();
        $r = $this->signe('/mere/sms/statuts', ['ids' => ['sms-0000000001', 'sms-inconnu-0001']])->assertOk();
        $this->assertSame('en_attente', $r->json('statuts.0.statut'));
        $this->assertSame('inconnu', $r->json('statuts.1.statut'));
        $this->assertStringNotContainsString('22900000001', (string) $r->getContent());
        Envoyeur::tourner(new PiloteJournal());
        $this->signe('/mere/sms/statuts', ['ids' => ['sms-0000000001']])->assertOk()->assertJson(['statuts' => [['id' => 'sms-0000000001', 'statut' => 'envoye', 'tentatives' => 1]]]);
        $this->signe('/mere/sms/statuts', ['ids' => 'sms-0000000001'])->assertStatus(422)->assertJson(['code' => 'ids_invalides']);
        $this->signe('/mere/sms/statuts', ['ids' => ['sms-0000000001']], null, 'sha256=00')->assertStatus(401);
    }

    public function test_l_etat_affiche_le_plafond_et_le_compte_du_jour_reserve_a_la_mere(): void
    {
        config(['relais.sms.plafond_jour' => 7]);
        $this->deposer()->assertOk();
        $this->getJson('/mere/sms/etat')->assertStatus(403);
        $this->getJson('/mere/sms/etat', ['x-mere' => self::SECRET])->assertOk()
            ->assertJson(['plafond_jour' => 7, 'envoyes_aujourdhui' => 0, 'en_attente' => 1, 'tentatives_max' => 5, 'pilote' => 'journal']);
    }

    // --- pilote HTTP générique -------------------------------------------------------------------------------------------------------------------

    public function test_le_pilote_http_lit_adresse_cle_et_champs_du_env_seulement(): void
    {
        Http::fake(['https://passerelle.exemple.invalid/*' => Http::response(['ok' => true], 200)]);
        $p = new PiloteHttp(['url' => 'https://passerelle.exemple.invalid/envoi', 'cle' => 'cle-essai', 'entete_cle' => 'X-Cle', 'prefixe_cle' => '', 'expediteur' => 'CLINIQUE',
            'champ_numero' => 'destinataire', 'champ_texte' => 'message', 'champ_expediteur' => 'expediteur']);
        $this->assertTrue($p->envoyer(self::NUMERO, 'Bonjour')->accepte);
        Http::assertSent(fn ($req) => $req->url() === 'https://passerelle.exemple.invalid/envoi' && $req->hasHeader('X-Cle', 'cle-essai')
            && $req['destinataire'] === self::NUMERO && $req['message'] === 'Bonjour' && $req['expediteur'] === 'CLINIQUE');
    }

    public function test_le_pilote_http_sans_adresse_ou_en_erreur_rend_un_code_jamais_le_corps(): void
    {
        $this->assertSame('pilote_non_configure', (new PiloteHttp([]))->envoyer(self::NUMERO, 'x')->code);
        Http::fake(['*' => Http::response('erreur : le numero +22900000001 est inconnu', 503)]);
        $r = (new PiloteHttp(['url' => 'https://passerelle.exemple.invalid/envoi']))->envoyer(self::NUMERO, 'x');
        $this->assertFalse($r->accepte);
        $this->assertSame('http_503', $r->code);
    }

    public function test_le_pilote_par_defaut_est_le_journal_qui_n_envoie_rien(): void
    {
        Http::fake();
        config(['relais.sms.pilote' => 'inconnu']);
        $this->assertSame('journal', Envoyeur::pilote()->nom());
        $this->deposer()->assertOk();
        Envoyeur::tourner();
        Http::assertNothingSent();
    }

    public function test_aucun_identifiant_de_fournisseur_n_est_ecrit_dans_le_depot(): void
    {
        $src = file_get_contents(config_path('relais.php')).file_get_contents(app_path('Relais/Sms/PiloteHttp.php'));
        $this->assertDoesNotMatchRegularExpression('#https?://(?!passerelle\.exemple)#', $src, 'aucune adresse de fournisseur en dur');
        $this->assertStringContainsString("env('RELAIS_SMS_HTTP_URL', '')", $src);
        $this->assertStringContainsString("env('RELAIS_SMS_HTTP_CLE', '')", $src);
    }

    // --- crochets du banc ------------------------------------------------------------------------------------------------------------------------

    public function test_les_crochets_du_banc_sont_fermes_hors_banc(): void
    {
        $this->postJson('/banc/sms/tourner')->assertStatus(404);
        $this->getJson('/banc/sms/tout')->assertStatus(404);
        config(['relais.banc' => true]);
        $this->deposer()->assertOk();
        $this->postJson('/banc/sms/tourner', ['pilote' => 'echec'])->assertOk()->assertJson(['echecs' => 1]);
    }
}
