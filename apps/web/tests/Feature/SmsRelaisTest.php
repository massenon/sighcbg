<?php

namespace Tests\Feature;

use App\Relais\Sms\Envoyeur;
use App\Relais\Sms\FileSms;
use App\Relais\Sms\Pilote;
use App\Relais\Sms\PiloteEchec;
use App\Relais\Sms\PiloteHttp;
use App\Relais\Sms\PiloteJournal;
use App\Relais\Sms\PiloteTwilio;
use App\Relais\Sms\PiloteVonage;
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
        config(['relais.sms.pilote' => 'journal']);
        $this->assertSame('journal', Envoyeur::pilote()->nom());
        $this->deposer()->assertOk();
        Envoyeur::tourner();
        Http::assertNothingSent();
    }

    public function test_un_nom_de_pilote_inconnu_est_un_echec_nomme_et_ne_touche_pas_la_file(): void
    {
        Http::fake();
        config(['relais.sms.pilote' => 'inconnu']);
        $this->assertSame('inconnu', Envoyeur::pilote()->nom());
        $this->deposer()->assertOk();
        $b = Envoyeur::tourner();
        $this->assertSame(0, $b['envoyes']);
        $this->assertSame(['RELAIS_SMS_PILOTE'], $b['configuration_manquante']);
        $this->assertSame('en_attente', DB::table('sms_sortants')->value('statut'));
        $this->assertNotNull(DB::table('sms_sortants')->value('texte'), 'le texte n\'est pas effacé pour une faute de .env');
        Http::assertNothingSent();
    }

    // --- pilotes Twilio et Vonage ----------------------------------------------------------------------------------------------------------------

    private function reglagesTwilio(array $sur = []): array
    {
        return $sur + ['url_base' => 'https://api.twilio.invalid/2010-04-01', 'sid' => 'ACessai0001', 'token' => 'jeton-essai', 'expediteur' => '+22900000009', 'service' => '', 'delai_s' => 5];
    }

    private function reglagesVonage(array $sur = []): array
    {
        return $sur + ['url' => 'https://rest.vonage.invalid/sms/json', 'cle' => 'cle-essai', 'secret' => 'secret-essai', 'expediteur' => 'CLINIQUE', 'delai_s' => 5];
    }

    public function test_le_pilote_twilio_poste_en_form_avec_auth_basic_sid_token(): void
    {
        Http::fake(['https://api.twilio.invalid/*' => Http::response(['sid' => 'SM1', 'status' => 'queued'], 201)]);
        $r = (new PiloteTwilio($this->reglagesTwilio()))->envoyer(self::NUMERO, 'Bonjour');
        $this->assertTrue($r->accepte);
        Http::assertSent(fn ($req) => $req->url() === 'https://api.twilio.invalid/2010-04-01/Accounts/ACessai0001/Messages.json'
            && $req->method() === 'POST'
            && $req->hasHeader('Authorization', 'Basic '.base64_encode('ACessai0001:jeton-essai'))
            && str_contains(implode(';', $req->header('Content-Type')), 'application/x-www-form-urlencoded')
            && $req['To'] === self::NUMERO && $req['From'] === '+22900000009' && $req['Body'] === 'Bonjour' && ! isset($req['MessagingServiceSid']));
    }

    public function test_le_pilote_twilio_prefere_le_service_de_messagerie_quand_il_est_regle(): void
    {
        Http::fake(['*' => Http::response([], 201)]);
        (new PiloteTwilio($this->reglagesTwilio(['expediteur' => '', 'service' => 'MGessai'])))->envoyer(self::NUMERO, 'x');
        Http::assertSent(fn ($req) => $req['MessagingServiceSid'] === 'MGessai' && ! isset($req['From']));
    }

    public function test_le_pilote_twilio_sans_parametres_nomme_ce_qui_manque_et_n_appelle_rien(): void
    {
        Http::fake();
        $p = new PiloteTwilio($this->reglagesTwilio(['sid' => '', 'token' => '', 'expediteur' => '']));
        $this->assertSame(['RELAIS_SMS_TWILIO_SID', 'RELAIS_SMS_TWILIO_TOKEN', 'RELAIS_SMS_EXPEDITEUR (ou RELAIS_SMS_TWILIO_SERVICE)'], $p->parametresManquants());
        $this->assertSame('twilio_parametre_manquant', $p->envoyer(self::NUMERO, 'x')->code);
        Http::assertNothingSent();
    }

    public function test_le_pilote_twilio_rend_un_code_jamais_le_corps(): void
    {
        Http::fake(['*' => Http::response('{"message":"The number +22900000001 is unverified"}', 401)]);
        $r = (new PiloteTwilio($this->reglagesTwilio()))->envoyer(self::NUMERO, 'x');
        $this->assertFalse($r->accepte);
        $this->assertSame('twilio_http_401', $r->code);
        $this->assertStringNotContainsString('2290', $r->code);
    }

    public function test_le_pilote_vonage_poste_l_api_sms_en_form_sans_le_plus(): void
    {
        Http::fake(['https://rest.vonage.invalid/*' => Http::response(['message-count' => '1', 'messages' => [['status' => '0', 'message-id' => 'abc']]], 200)]);
        $r = (new PiloteVonage($this->reglagesVonage()))->envoyer(self::NUMERO, 'Bonjour');
        $this->assertTrue($r->accepte);
        Http::assertSent(fn ($req) => $req->url() === 'https://rest.vonage.invalid/sms/json' && $req->method() === 'POST'
            && str_contains(implode(';', $req->header('Content-Type')), 'application/x-www-form-urlencoded')
            && $req['api_key'] === 'cle-essai' && $req['api_secret'] === 'secret-essai' && $req['from'] === 'CLINIQUE'
            && $req['to'] === '22900000001' && $req['text'] === 'Bonjour');
    }

    public function test_le_pilote_vonage_lit_le_statut_du_corps_car_un_refus_repond_200(): void
    {
        Http::fake(['*' => Http::sequence()
            ->push(['messages' => [['status' => '9', 'error-text' => 'Quota Exceeded pour +22900000001']]], 200)
            ->push('pas du json', 200)
            ->push('', 503)]);
        $p = new PiloteVonage($this->reglagesVonage());
        $r = $p->envoyer(self::NUMERO, 'x');
        $this->assertFalse($r->accepte);
        $this->assertSame('vonage_statut_9', $r->code);
        $this->assertSame('vonage_reponse_illisible', $p->envoyer(self::NUMERO, 'x')->code);
        $this->assertSame('vonage_http_503', $p->envoyer(self::NUMERO, 'x')->code);
    }

    public function test_le_pilote_vonage_sans_parametres_nomme_ce_qui_manque_et_n_appelle_rien(): void
    {
        Http::fake();
        $p = new PiloteVonage($this->reglagesVonage(['cle' => '', 'secret' => '']));
        $this->assertSame(['RELAIS_SMS_VONAGE_CLE', 'RELAIS_SMS_VONAGE_SECRET'], $p->parametresManquants());
        $this->assertSame('vonage_parametre_manquant', $p->envoyer(self::NUMERO, 'x')->code);
        Http::assertNothingSent();
    }

    public function test_le_choix_du_fournisseur_est_un_reglage_et_une_config_incomplete_ne_brule_aucune_tentative(): void
    {
        Http::fake();
        foreach (['twilio' => PiloteTwilio::class, 'vonage' => PiloteVonage::class] as $nom => $classe) {
            config(['relais.sms.pilote' => $nom, 'relais.sms.twilio' => [], 'relais.sms.vonage' => []]);
            $this->assertInstanceOf($classe, Envoyeur::pilote());
        }
        $this->deposer()->assertOk();
        $b = Envoyeur::tourner();
        $this->assertNotSame([], $b['configuration_manquante']);
        $this->assertSame(0, (int) DB::table('sms_sortants')->value('tentatives'));
        $this->assertSame('en_attente', DB::table('sms_sortants')->value('statut'));
        $this->assertNotNull(DB::table('sms_sortants')->value('texte'));
        $this->assertStringNotContainsString(self::NUMERO, $this->auditSms());
        $this->assertStringNotContainsString('secret', $this->auditSms());
        $this->assertStringContainsString('sms_pilote_non_configure', $this->auditSms());
        Http::assertNothingSent();
    }

    public function test_l_etat_dit_les_parametres_manquants_du_pilote_sans_leurs_valeurs(): void
    {
        config(['relais.sms.pilote' => 'vonage', 'relais.sms.vonage' => $this->reglagesVonage(['secret' => ''])]);
        $this->getJson('/mere/sms/etat', ['x-mere' => self::SECRET])->assertOk()
            ->assertJson(['pilote' => 'vonage', 'parametres_manquants' => ['RELAIS_SMS_VONAGE_SECRET']]);
    }

    public function test_un_envoi_vonage_accepte_efface_le_numero_et_le_texte_et_reutilise_le_plafond(): void
    {
        Http::fake(['*' => Http::response(['messages' => [['status' => '0']]], 200)]);
        config(['relais.sms.pilote' => 'vonage', 'relais.sms.vonage' => $this->reglagesVonage(), 'relais.sms.plafond_jour' => 1]);
        $this->deposer('sms-0000000001')->assertOk();
        $this->assertSame(1, Envoyeur::tourner()['envoyes']);
        $l = DB::table('sms_sortants')->first();
        $this->assertSame('envoye', $l->statut);
        $this->assertNull($l->numero);
        $this->assertNull($l->texte);
        $this->assertStringNotContainsString('secret-essai', $this->auditSms());
        $this->deposer('sms-0000000002')->assertStatus(429);
    }

    public function test_aucun_identifiant_de_fournisseur_n_est_ecrit_dans_le_depot(): void
    {
        $src = file_get_contents(config_path('relais.php')).file_get_contents(app_path('Relais/Sms/PiloteHttp.php'));
        // Les deux seules adresses tolérées sont les API documentées de Twilio et de Vonage, valeurs PAR DÉFAUT d'un réglage surchargeable (RELAIS_SMS_*_URL*).
        $this->assertDoesNotMatchRegularExpression('#https?://(?!passerelle\.exemple|api\.twilio\.com/2010-04-01|rest\.nexmo\.com/sms/json)#', $src, 'aucune adresse de fournisseur en dur');
        foreach (['PiloteTwilio', 'PiloteVonage'] as $c) {
            $this->assertDoesNotMatchRegularExpression('#https?://#', file_get_contents(app_path("Relais/Sms/{$c}.php")).'', 'le pilote lit son adresse du réglage');
        }
        $this->assertStringContainsString("env('RELAIS_SMS_HTTP_URL', '')", $src);
        $this->assertStringContainsString("env('RELAIS_SMS_HTTP_CLE', '')", $src);
    }

    // --- durée de validité d'un SMS en attente (E5204) -----------------------------------------------------------------------------------------------

    /** Dépose un SMS puis le vieillit : `depose_le` recule de [heures] heures. */
    private function deposerVieux(string $id, int $heures): void
    {
        $this->deposer($id)->assertOk();
        $vieux = (int) (microtime(true) * 1000) - $heures * 3600000;
        DB::table('sms_sortants')->where('uid', $id)->update(['depose_le' => $vieux, 'prochain_essai_le' => $vieux]);
    }

    public function test_un_sms_perime_est_abandonne_avec_un_statut_nomme_et_son_numero_et_son_texte_sont_effaces(): void
    {
        config(['relais.sms.validite_heures' => 24]);
        $this->deposerVieux('sms-perime-0001', 25);
        $this->deposer('sms-frais-00001')->assertOk();
        $b = Envoyeur::tourner(new PiloteJournal());
        $this->assertSame(1, $b['expires']);
        $this->assertSame(1, $b['envoyes'], 'seul le SMS frais part');
        $l = DB::table('sms_sortants')->where('uid', 'sms-perime-0001')->first();
        $this->assertSame('expire', $l->statut);
        $this->assertSame('expire', $l->derniere_erreur);
        $this->assertNotNull($l->expire_le);
        $this->assertNull($l->numero);
        $this->assertNull($l->texte);
        $this->assertSame(0, (int) $l->tentatives, 'jamais tenté : il n\'est pas parti');
        $this->assertNull($l->envoye_le);
        $a = $this->auditSms();
        $this->assertStringContainsString('sms_expire', $a);
        $this->assertStringNotContainsString('22900000001', $a);
        $this->assertStringNotContainsString('rendez-vous', $a);
    }

    public function test_un_sms_retenu_par_le_plafond_ne_part_pas_le_lendemain_s_il_est_perime(): void
    {
        config(['relais.sms.plafond_jour' => 1, 'relais.sms.validite_heures' => 24]);
        $this->deposer('sms-0000000001')->assertOk();
        Envoyeur::tourner(new PiloteJournal());
        // Le plafond du jour est atteint : le deuxième SMS attend (plafond relevé le temps du dépôt).
        config(['relais.sms.plafond_jour' => 2]);
        $this->deposer('sms-0000000002')->assertOk();
        config(['relais.sms.plafond_jour' => 1]);
        $b = Envoyeur::tourner(new PiloteJournal());
        $this->assertSame(0, $b['envoyes']);
        $this->assertTrue($b['plafond_atteint']);
        $this->assertSame('en_attente', DB::table('sms_sortants')->where('uid', 'sms-0000000002')->value('statut'));
        // Le lendemain, 25 heures plus tard : le plafond est levé, mais le SMS est périmé — il est abandonné, il ne part pas.
        $b = Envoyeur::tourner(new PiloteJournal(), (int) (microtime(true) * 1000) + 25 * 3600000);
        $this->assertSame(1, $b['expires']);
        $this->assertSame(0, $b['envoyes']);
        $l = DB::table('sms_sortants')->where('uid', 'sms-0000000002')->first();
        $this->assertSame('expire', $l->statut);
        $this->assertNull($l->numero);
        $this->assertNull($l->texte);
    }

    public function test_un_sms_encore_valide_reste_en_attente_et_la_duree_se_regle(): void
    {
        config(['relais.sms.validite_heures' => 48]);
        $this->deposerVieux('sms-0000000001', 30);
        $this->assertSame(0, Envoyeur::expirer());
        $this->assertSame('en_attente', DB::table('sms_sortants')->value('statut'));
        config(['relais.sms.validite_heures' => 24]);
        $this->assertSame(1, Envoyeur::expirer());
        $this->assertSame('expire', DB::table('sms_sortants')->value('statut'));
        // jamais illimitée : zéro ou négatif retombe sur une heure au moins
        config(['relais.sms.validite_heures' => 0]);
        $this->assertSame(3600000, FileSms::validiteMs());
    }

    public function test_un_pilote_mal_configure_n_empeche_pas_d_abandonner_les_perimes(): void
    {
        Http::fake();
        config(['relais.sms.pilote' => 'inconnu', 'relais.sms.validite_heures' => 24]);
        $this->deposerVieux('sms-perime-0001', 30);
        $this->deposer('sms-frais-00001')->assertOk();
        $b = Envoyeur::tourner();
        $this->assertSame(1, $b['expires']);
        $this->assertSame(['RELAIS_SMS_PILOTE'], $b['configuration_manquante']);
        $this->assertNull(DB::table('sms_sortants')->where('uid', 'sms-perime-0001')->value('texte'), 'le périmé est effacé même sans pilote');
        $this->assertNotNull(DB::table('sms_sortants')->where('uid', 'sms-frais-00001')->value('texte'), 'le frais n\'est pas touché pour une faute de .env');
        Http::assertNothingSent();
    }

    public function test_la_mere_voit_le_statut_expire_et_un_depot_rejoue_ne_ressuscite_pas_le_sms(): void
    {
        $this->deposerVieux('sms-perime-0001', 30);
        Envoyeur::tourner(new PiloteJournal());
        $r = $this->signe('/mere/sms/statuts', ['ids' => ['sms-perime-0001']])->assertOk();
        $this->assertSame('expire', $r->json('statuts.0.statut'));
        $this->assertNotNull($r->json('statuts.0.expire_le'));
        $this->assertStringNotContainsString('22900000001', (string) $r->getContent());
        $rejeu = $this->deposer('sms-perime-0001')->assertOk();
        $this->assertTrue($rejeu->json('rejeu'));
        $this->assertSame('expire', $rejeu->json('sms.statut'));
        $this->assertNull(DB::table('sms_sortants')->where('uid', 'sms-perime-0001')->value('texte'));
    }

    public function test_l_etat_annonce_la_validite_et_les_expires_sont_purges_apres_la_conservation(): void
    {
        config(['relais.sms.validite_heures' => 12, 'relais.sms.conservation_jours' => 30]);
        $this->getJson('/mere/sms/etat', ['x-mere' => self::SECRET])->assertOk()->assertJson(['validite_heures' => 12]);
        $vieux = (int) (microtime(true) * 1000) - 31 * 86400000;
        DB::table('sms_sortants')->insert(['uid' => 'sms-vieux-expire', 'longueur' => 1, 'statut' => 'expire', 'tentatives' => 0, 'depose_le' => $vieux, 'prochain_essai_le' => $vieux, 'expire_le' => $vieux, 'efface_le' => $vieux, 'numero' => null, 'texte' => null]);
        $this->assertSame(1, Envoyeur::purger());
    }

    public function test_la_validite_est_un_reglage_du_env_jamais_une_valeur_ecrite_dans_le_code(): void
    {
        $this->assertStringContainsString("env('RELAIS_SMS_VALIDITE_HEURES', 24)", file_get_contents(config_path('relais.php')));
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
