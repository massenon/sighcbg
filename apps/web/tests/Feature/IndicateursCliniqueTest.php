<?php

namespace Tests\Feature;

use App\Livewire\Panneau\TableauClinique;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;
use Livewire\Livewire;
use Tests\Concerns\AvecInstantanesClinique;
use Tests\TestCase;

/**
 * Direction, 09/11/2026 (ADR-0007) : le relais accepte de la mère des indicateurs AGRÉGÉS NON NOMINATIFS, et un tableau de bord superadmin les montre en
 * LECTURE SEULE. Ces tests prouvent : la publication acceptée, le refus de tout champ inattendu ou nominatif, le refus d'un secret ou d'une signature faux,
 * la réserve au superadmin, l'état « jamais publié » en toutes lettres, et l'absence de toute écriture depuis la page.
 */
class IndicateursCliniqueTest extends TestCase
{
    use AvecInstantanesClinique;
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        config(['relais.secret_mere' => self::SECRET_INDICATEURS, 'relais.indicateurs_clinique_max' => 500, 'relais.seuil_indicateurs_clinique_ms' => 3600000]);
    }

    private function superadmin(): User
    {
        return User::factory()->create(['email' => 'admin'.bin2hex(random_bytes(3)).'@clinique.test']);
    }

    // --- la publication ---------------------------------------------------------------------------------------------------------------------

    public function test_un_instantane_signe_et_conforme_est_accepte_et_conserve(): void
    {
        $i = $this->instantane();
        $this->publier(['instantane' => $i])->assertOk()->assertJson(['ok' => true]);
        $this->assertDatabaseCount('indicateurs_clinique', 1);
        $ligne = DB::table('indicateurs_clinique')->first();
        $this->assertSame($i['genere_le'], (int) $ligne->genere_le);
        $this->assertSame($i, json_decode($ligne->charge, true));
    }

    public function test_un_champ_inattendu_ou_nominatif_est_refuse_et_rien_n_est_ecrit(): void
    {
        $cas = [
            'champ nominatif à la racine' => ['nom_patient' => 'ZANTCHEDE Kadidja'],
            'champ libre dans un groupe' => ['patients' => ['commentaire' => 'Kadidja est venue']],
            'téléphone' => ['telephone' => '00 00 00 00 02'],
            'diagnostic' => ['activite_mois' => ['diagnostic' => 'Paludisme grave']],
        ];
        foreach ($cas as $nom => $ajout) {
            $i = array_replace_recursive($this->instantane(), $ajout);
            $r = $this->publier(['instantane' => $i]);
            $r->assertStatus(422)->assertJson(['code' => 'instantane_invalide']);
            $this->assertStringContainsString('champ inattendu', $r->json('motif'), $nom);
            $this->assertStringNotContainsString('Kadidja', (string) $r->getContent(), 'le refus ne répète jamais la valeur reçue : '.$nom);
        }
        $this->assertDatabaseCount('indicateurs_clinique', 0);
    }

    public function test_une_chaine_libre_ou_un_type_inattendu_sont_refuses(): void
    {
        $mauvais = [
            ['patients' => ['actifs' => 'beaucoup']],
            ['patients' => ['actifs' => 12.5]],
            ['patients' => ['actifs' => -1]],
            ['facturation_mois' => ['montant_facture' => '1520000']],
            ['comptabilite' => ['prochaine_echeance_code' => 'Paiement du fournisseur Pharma Borgou']],
            ['comptabilite' => ['prochaine_echeance_date' => '12 novembre']],
            ['version_application' => 'Clinique de ZANTCHEDE'],
            ['etat_jeu' => 'prod'],
            ['taux_occupation_lits_pct' => 140],
            ['postes' => [['appareil' => 'Poste de VODOUHE Fiacre', 'derniere_synchro' => 1]]],
            ['schema' => 2],
        ];
        foreach ($mauvais as $m) {
            $this->publier(['instantane' => array_replace_recursive($this->instantane(), $m)])->assertStatus(422)->assertJson(['code' => 'instantane_invalide']);
        }
        $this->assertDatabaseCount('indicateurs_clinique', 0);
    }

    public function test_un_champ_manquant_et_un_corps_sans_instantane_unique_sont_refuses(): void
    {
        $i = $this->instantane();
        unset($i['stock']);
        $this->publier(['instantane' => $i])->assertStatus(422);
        $this->publier(['instantane' => $this->instantane(), 'autre' => 'x'])->assertStatus(422);
        $this->publier(['instantane' => 'texte'])->assertStatus(422);
        $this->publier([])->assertStatus(422);
        $this->publier(['ne' => 'pas json'], null, null, 'ceci n\'est pas du json')->assertStatus(422);
        $this->assertDatabaseCount('indicateurs_clinique', 0);
    }

    public function test_les_valeurs_non_disponibles_sont_permises_et_les_postes_bornes(): void
    {
        $i = $this->instantane(['patients' => ['actifs' => null], 'taux_occupation_lits_pct' => null, 'comptabilite' => ['prochaine_echeance_code' => null, 'prochaine_echeance_date' => null]]);
        $i['postes'] = [];
        $this->publier(['instantane' => $i])->assertOk();
        $trop = $this->instantane(['genere_le' => $i['genere_le'] + 10]);
        $trop['postes'] = array_map(fn ($n) => ['appareil' => 'p'.$n, 'derniere_synchro' => 1], range(1, 60));
        $this->publier(['instantane' => $trop])->assertStatus(422);
    }

    public function test_un_secret_invalide_est_refuse(): void
    {
        $this->publier(['instantane' => $this->instantane()], 'mauvais-secret')->assertStatus(403)->assertJson(['code' => 'mere_requise']);
        $this->postJson('/mere/indicateurs-clinique', ['instantane' => $this->instantane()])->assertStatus(403);
        config(['relais.secret_mere' => '']);
        $this->publier(['instantane' => $this->instantane()], '')->assertStatus(403);
        $this->assertDatabaseCount('indicateurs_clinique', 0);
    }

    public function test_une_signature_absente_fausse_ou_sur_un_autre_corps_est_refusee(): void
    {
        $i = $this->instantane();
        $this->publier(['instantane' => $i], null, 'sha256=00')->assertStatus(401)->assertJson(['code' => 'signature_invalide']);
        $this->publier(['instantane' => $i], null, '')->assertStatus(401);
        // Signature d'un autre secret : refusée même avec le bon x-mere.
        $brut = json_encode(['instantane' => $i]);
        $this->publier(['instantane' => $i], null, 'sha256='.hash_hmac('sha256', $brut, 'autre-secret'))->assertStatus(401);
        // Corps altéré en route : on signe un instantané puis on en envoie un autre.
        $altere = $this->instantane(['patients' => ['actifs' => 999]]);
        $signe = 'sha256='.hash_hmac('sha256', $brut, self::SECRET_INDICATEURS);
        $this->publier(['instantane' => $altere], null, $signe)->assertStatus(401);
        $this->assertDatabaseCount('indicateurs_clinique', 0);
        $this->assertDatabaseHas('relais_audit', ['action' => 'indicateurs_clinique_refuse', 'detail' => 'signature_invalide']);
    }

    public function test_un_corps_trop_gros_est_refuse_sans_etre_lu(): void
    {
        config(['relais.indicateurs_clinique_octets_max' => 200]);
        $this->publier(['instantane' => $this->instantane()])->assertStatus(413)->assertJson(['code' => 'corps_trop_gros']);
    }

    public function test_un_instantane_rejoue_ou_perime_ou_date_du_futur_est_refuse(): void
    {
        $i = $this->instantane();
        $this->publier(['instantane' => $i])->assertOk();
        $this->publier(['instantane' => $i])->assertStatus(409)->assertJson(['code' => 'instantane_deja_recu']);
        $ancien = $this->instantane(['genere_le' => $i['genere_le'] - 5000]);
        $this->publier(['instantane' => $ancien])->assertStatus(409)->assertJson(['code' => 'instantane_perime']);
        $futur = $this->instantane(['genere_le' => (int) (microtime(true) * 1000) + 3600000]);
        $this->publier(['instantane' => $futur])->assertStatus(422);
        $this->assertDatabaseCount('indicateurs_clinique', 1);
    }

    public function test_la_conservation_est_bornee_aux_n_derniers(): void
    {
        config(['relais.indicateurs_clinique_max' => 3]);
        $base = (int) (microtime(true) * 1000) - 100000;
        foreach (range(1, 6) as $n) {
            $this->publier(['instantane' => $this->instantane(['genere_le' => $base + $n * 1000])])->assertOk();
        }
        $this->assertDatabaseCount('indicateurs_clinique', 3);
        $this->assertSame([$base + 4000, $base + 5000, $base + 6000], DB::table('indicateurs_clinique')->orderBy('genere_le')->pluck('genere_le')->map(fn ($v) => (int) $v)->all());
    }

    public function test_la_route_n_accepte_que_post_et_n_expose_aucune_lecture_publique(): void
    {
        $this->getJson('/mere/indicateurs-clinique', ['x-mere' => self::SECRET_INDICATEURS])->assertStatus(405);
    }

    public function test_les_indicateurs_historiques_du_relais_sont_inchanges(): void
    {
        $this->postJson('/mere/indicateurs', ['indicateurs' => ['patients_actifs' => 3]], ['x-mere' => self::SECRET_INDICATEURS])->assertOk();
        $this->assertDatabaseCount('relais_indicateurs_historique', 1);
        $this->assertDatabaseCount('indicateurs_clinique', 0);
    }

    // --- la page ----------------------------------------------------------------------------------------------------------------------------

    public function test_la_page_est_fermee_aux_visiteurs_et_ouverte_au_superadmin(): void
    {
        $this->get('/panneau/clinique')->assertRedirect('/panneau/connexion');
        $this->actingAs($this->superadmin())->get('/panneau/clinique')->assertOk()->assertSee('Tableau de bord de la clinique');
    }

    public function test_jamais_publie_est_une_phrase_pas_un_tableau_vide(): void
    {
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)
            ->assertSee('Jamais publié')
            ->assertSee('fermé par défaut')
            ->assertSee('ce tableau reste vide, et c’est voulu')
            ->assertDontSee('data-indicateur', false)
            ->assertDontSee('Patients actifs');
    }

    public function test_la_note_permanente_dit_ce_que_le_relais_voit_et_ne_voit_pas_meme_sans_donnee(): void
    {
        $vide = Livewire::actingAs($this->superadmin())->test(TableauClinique::class);
        $this->publier(['instantane' => $this->instantane()])->assertOk();
        $plein = Livewire::actingAs($this->superadmin())->test(TableauClinique::class);
        foreach ([$vide, $plein] as $page) {
            $page->assertSee('Ce que le relais voit.')->assertSee('agrégats non nominatifs')
                ->assertSee('Ce que le relais ne voit toujours pas.')->assertSee('enveloppes chiffrées de bout en bout');
        }
    }

    public function test_les_cartes_montrent_valeur_variation_et_fraicheur(): void
    {
        $maintenant = (int) (microtime(true) * 1000);
        $this->publier(['instantane' => $this->instantane(['genere_le' => $maintenant - 2000, 'patients' => ['actifs' => 110], 'facturation_mois' => ['reste_du' => 600000], 'stock' => ['articles_sous_seuil' => 4]])])->assertOk();
        $this->publier(['instantane' => $this->instantane(['genere_le' => $maintenant - 1000, 'patients' => ['actifs' => 120], 'facturation_mois' => ['reste_du' => 540000], 'stock' => ['articles_sous_seuil' => 4]])])->assertOk();
        $page = Livewire::actingAs($this->superadmin())->test(TableauClinique::class);
        $page->assertSee('Patients actifs')->assertSee('120')->assertSee('+10')
            ->assertSee('Reste dû du mois')->assertSee("540\u{202F}000\u{00A0}FCFA")->assertSee("−60\u{202F}000\u{00A0}FCFA")
            ->assertSee('stable')
            ->assertSee('À jour')->assertSee('Dernier instantané reçu il y a')
            ->assertSee('AIB')->assertSee('12/11/2026')->assertSee('1.4.2')->assertSee('démonstration')
            ->assertSee('poste-a1');
        // Une hausse du reste dû est mauvaise, une baisse bonne : le ton suit le sens de l'indicateur.
        $this->assertStringContainsString('puce ok" title="Variation par rapport à l’instantané précédent">−60', preg_replace('/\s+/', ' ', str_replace("\u{202F}", "\u{202F}", $page->html())) ?? '');
    }

    public function test_une_valeur_non_disponible_ne_s_affiche_pas_comme_zero(): void
    {
        $this->publier(['instantane' => $this->instantane(['patients' => ['actifs' => null], 'taux_occupation_lits_pct' => null])])->assertOk();
        $html = Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->html();
        $this->assertMatchesRegularExpression('/data-indicateur="patients_actifs".*?non disponible/s', $html);
        $this->assertMatchesRegularExpression('/data-indicateur="occupation".*?non disponible/s', $html);
    }

    public function test_un_instantane_trop_ancien_leve_l_alerte_de_fraicheur(): void
    {
        $this->publier(['instantane' => $this->instantane()])->assertOk();
        DB::table('indicateurs_clinique')->update(['recu_le' => (int) (microtime(true) * 1000) - 3 * 3600000]);
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->assertSee('Trop ancien')->assertSee('La mère ne publie plus');
    }

    public function test_le_seuil_d_anciennete_suit_l_intervalle_observe(): void
    {
        $maintenant = (int) (microtime(true) * 1000);
        $this->publier(['instantane' => $this->instantane(['genere_le' => $maintenant - 3000])])->assertOk();
        $this->publier(['instantane' => $this->instantane(['genere_le' => $maintenant - 2000])])->assertOk();
        $ids = DB::table('indicateurs_clinique')->orderBy('id')->pluck('id')->all();
        // La mère publie une fois par jour : 4 h de silence n'est pas une anomalie, 3 jours oui.
        DB::table('indicateurs_clinique')->where('id', $ids[0])->update(['recu_le' => $maintenant - 86400000 - 4 * 3600000]);
        DB::table('indicateurs_clinique')->where('id', $ids[1])->update(['recu_le' => $maintenant - 4 * 3600000]);
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->assertSee('À jour')->assertDontSee('Trop ancien');
        DB::table('indicateurs_clinique')->where('id', $ids[1])->update(['recu_le' => $maintenant - 3 * 86400000]);
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->assertSee('Trop ancien');
    }

    public function test_le_graphique_d_evolution_se_trace_et_se_choisit(): void
    {
        $base = (int) (microtime(true) * 1000) - 10000;
        foreach ([100, 120, 90] as $n => $actifs) {
            $this->publier(['instantane' => $this->instantane(['genere_le' => $base + $n * 1000, 'patients' => ['actifs' => $actifs]])])->assertOk();
        }
        $page = Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->set('courbe', 'patients_actifs');
        $page->assertSee('Évolution sur les derniers instantanés')->assertSee('Patients actifs : de 90 à 120');
        $this->assertStringContainsString('<polyline class="courbe-trait"', $page->html());
        $this->assertSame(3, substr_count($page->html(), 'class="courbe-point"'));
        // Un nom de courbe inconnu retombe sur la courbe par défaut, il ne casse rien.
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->set('courbe', 'nom_inconnu')->assertSee('Montant facturé du mois');
    }

    // --- lecture seule ----------------------------------------------------------------------------------------------------------------------

    public function test_lecture_seule_aucune_route_d_ecriture_depuis_la_page(): void
    {
        $routes = collect(Route::getRoutes()->getRoutes())->filter(fn ($r) => str_starts_with($r->uri(), 'panneau/clinique'));
        $this->assertCount(1, $routes);
        $this->assertSame(['GET', 'HEAD'], $routes->first()->methods());
        foreach (['POST', 'PUT', 'PATCH', 'DELETE'] as $verbe) {
            $this->actingAs($this->superadmin())->call($verbe, '/panneau/clinique')->assertStatus(405);
        }
    }

    public function test_lecture_seule_le_composant_n_expose_aucune_action_et_la_page_aucune_commande(): void
    {
        $actions = collect((new \ReflectionClass(TableauClinique::class))->getMethods(\ReflectionMethod::IS_PUBLIC))
            ->filter(fn ($m) => $m->class === TableauClinique::class)->map(fn ($m) => $m->name)->all();
        $this->assertSame(['render'], $actions, 'la page ne déclare que son rendu : aucune action appelable depuis le navigateur');
        $this->publier(['instantane' => $this->instantane()])->assertOk();
        $html = Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->html();
        foreach (['wire:click', 'wire:submit', '<form', '<button', 'type="submit"', 'type="password"', '<textarea'] as $commande) {
            $this->assertStringNotContainsString($commande, $html, 'commande d\'écriture trouvée : '.$commande);
        }
    }

    public function test_lecture_seule_afficher_ou_choisir_une_courbe_n_ecrit_rien(): void
    {
        $this->publier(['instantane' => $this->instantane()])->assertOk();
        $avant = ['i' => DB::table('indicateurs_clinique')->get()->toJson(), 'm' => DB::table('relais_meta')->get()->toJson(), 'a' => DB::table('relais_appareils')->count()];
        Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->set('courbe', 'reste_du')->set('courbe', 'patients_actifs');
        $this->assertSame($avant, ['i' => DB::table('indicateurs_clinique')->get()->toJson(), 'm' => DB::table('relais_meta')->get()->toJson(), 'a' => DB::table('relais_appareils')->count()]);
    }

    public function test_aucune_donnee_nominative_en_base_ni_a_l_ecran_apres_un_envoi_conforme(): void
    {
        $this->publier(['instantane' => $this->instantane()])->assertOk();
        $html = Livewire::actingAs($this->superadmin())->test(TableauClinique::class)->html();
        $charge = (string) DB::table('indicateurs_clinique')->value('charge');
        foreach (['ZANTCHEDE', 'Kadidja', 'CBG/', 'Pharma', 'Paludisme'] as $nom) {
            $this->assertStringNotContainsString($nom, $charge.$html);
        }
    }

    public function test_le_menu_du_panneau_propose_le_tableau_de_bord_de_la_clinique(): void
    {
        $this->actingAs($this->superadmin())->get('/panneau')->assertOk()->assertSee('Tableau de bord de la clinique')->assertSee(route('panneau.clinique'), false);
    }
}
