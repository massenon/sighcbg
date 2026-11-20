<?php

namespace Tests\Feature\Panneau;

use App\Models\User;
use App\Relais\Sms\FileSms;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\TestCase;

/**
 * E5205 : la section « SMS du relais » du panneau superadmin (ADR-0009). Elle montre le pilote en service, les NOMS des paramètres manquants, le plafond et les envoyés
 * du jour, les compteurs de la file, des échecs et des expirés. Jamais un numéro, jamais un texte, jamais la valeur d'un réglage du `.env`.
 *
 * Écrits le 20/11/2026, NON EXÉCUTÉS dans l'environnement de l'agent (pas de vendor/ : `composer install` y est proscrit). À lancer : `php artisan test --filter=PanneauSmsTest`.
 */
class PanneauSmsTest extends TestCase
{
    use RefreshDatabase;

    private const NUMERO = '+22900000077';

    private const TEXTE = 'TEXTE-SENTINELLE-PANNEAU rendez-vous demain';

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.sms.pilote' => 'journal', 'relais.sms.plafond_jour' => 100, 'relais.sms.validite_heures' => 24, 'relais.sms.tentatives_max' => 5]);
    }

    private function admin(): User
    {
        return User::factory()->create(['email' => 'admin@clinique.test', 'password' => Hash::make('ancien-mot-de-passe-12')]);
    }

    private function ligne(string $uid, string $statut, array $plus = []): void
    {
        $m = (int) (microtime(true) * 1000);
        DB::table('sms_sortants')->insert($plus + [
            'uid' => $uid, 'numero' => $statut === 'en_attente' ? self::NUMERO : null, 'texte' => $statut === 'en_attente' ? self::TEXTE : null, 'longueur' => 40,
            'statut' => $statut, 'tentatives' => 0, 'depose_le' => $m, 'prochain_essai_le' => $m,
            'envoye_le' => $statut === 'envoye' ? $m : null, 'efface_le' => $statut === 'en_attente' ? null : $m,
        ]);
    }

    public function test_la_section_sms_est_sur_la_page_superadmin_et_ferme_aux_visiteurs(): void
    {
        $this->get(route('panneau.superadmin'))->assertRedirect('/panneau/connexion');
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()->assertSee('SMS du relais')->assertSee('Pilote en service');
    }

    public function test_le_pilote_d_essai_est_dit_il_n_envoie_rien(): void
    {
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()->assertSee('journal')->assertSee('essai : n’envoie rien');
        $this->assertFalse(FileSms::resume()['envoie']);
    }

    public function test_les_parametres_manquants_sont_nommes_jamais_leurs_valeurs(): void
    {
        config(['relais.sms.pilote' => 'vonage', 'relais.sms.vonage' => ['url' => 'https://rest.vonage.invalid/sms/json', 'cle' => 'CLE-SECRETE-SENTINELLE', 'secret' => '', 'expediteur' => 'CLINIQUE', 'delai_s' => 5]]);
        $r = $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk();
        $r->assertSee('vonage')->assertSee('RELAIS_SMS_VONAGE_SECRET')->assertSee('envoie réellement');
        $r->assertDontSee('CLE-SECRETE-SENTINELLE');
        $this->assertSame(['RELAIS_SMS_VONAGE_SECRET'], FileSms::resume()['parametres_manquants']);
    }

    public function test_aucun_parametre_manquant_est_dit_aucun(): void
    {
        $this->assertSame([], FileSms::resume()['parametres_manquants']);
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()->assertSee('Paramètres manquants')->assertSee('aucun');
    }

    public function test_le_plafond_et_les_envoyes_du_jour_sont_affiches(): void
    {
        config(['relais.sms.plafond_jour' => 2]);
        $this->ligne('sms-env-000001', 'envoye');
        $this->ligne('sms-env-000002', 'envoye');
        $r = FileSms::resume();
        $this->assertSame(2, $r['plafond_jour']);
        $this->assertSame(2, $r['envoyes_aujourdhui']);
        $this->assertTrue($r['plafond_atteint']);
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()->assertSee('2 envoyé(s) sur 2')->assertSee('plafond atteint');
    }

    public function test_les_compteurs_de_la_file_des_echecs_et_des_expires(): void
    {
        $vieux = (int) (microtime(true) * 1000) - 2 * 3600000;
        $this->ligne('sms-att-000001', 'en_attente');
        $this->ligne('sms-att-000002', 'en_attente', ['depose_le' => $vieux]);
        $this->ligne('sms-ech-000001', 'echec', ['tentatives' => 5]);
        $this->ligne('sms-exp-000001', 'expire');
        $this->ligne('sms-exp-000002', 'expire');
        $r = FileSms::resume();
        $this->assertSame(2, $r['file']);
        $this->assertSame(1, $r['file_en_retard']);
        $this->assertSame(1, $r['echecs']);
        $this->assertSame(2, $r['expires']);
        $this->assertSame(24, $r['validite_heures']);
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()
            ->assertSee('2 en attente')->assertSee('1 depuis plus d’une heure')->assertSee('Échecs')->assertSee('Expirés');
    }

    public function test_ni_numero_ni_texte_ni_identifiant_de_sms_n_apparaissent(): void
    {
        $this->ligne('sms-att-000001', 'en_attente');
        $page = (string) $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk()->getContent();
        $this->assertStringNotContainsString('22900000077', $page);
        $this->assertStringNotContainsString('SENTINELLE-PANNEAU', $page);
        $this->assertStringNotContainsString('sms-att-000001', $page);
        $json = json_encode(FileSms::resume());
        $this->assertStringNotContainsString('22900000077', $json);
        $this->assertStringNotContainsString('SENTINELLE', $json);
    }

    public function test_le_formulaire_de_mot_de_passe_annonce_le_minimum_du_reglage_et_non_huit(): void
    {
        $r = $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertOk();
        $r->assertSee('Nouveau mot de passe (12 caractères au moins)', false)->assertDontSee('8 caractères au moins');
        config(['relais.mdp_superadmin_min' => 14]);
        $this->actingAs($this->admin())->get(route('panneau.superadmin'))->assertSee('Nouveau mot de passe (14 caractères au moins)', false);
    }
}
