<?php

namespace App\Livewire\Panneau;

use App\Relais\Format;
use App\Relais\VueIndicateurs;
use App\Relais\IndicateursClinique;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * TABLEAU DE BORD DE LA CLINIQUE : LECTURE SEULE (Direction, 09/11/2026, ADR-0007).
 *
 * Il affiche les indicateurs AGRÉGÉS NON NOMINATIFS que la mère publie quand son interrupteur est ouvert. Il ne lit aucun dossier (enveloppes chiffrées de
 * bout en bout), ne modifie aucun paramètre de la clinique et n'expose aucune commande d'écriture : la seule propriété publique est le choix de la courbe
 * affichée, qui ne touche à rien. Réservé aux comptes superadmin (middleware `auth` : tout compte du panneau est un superadmin).
 */
#[Layout('layouts.panneau')]
class TableauClinique extends Component
{
    /** Courbe affichée (clé de CARTES). Choix d'affichage seulement : aucune donnée n'est écrite. */
    #[Url(as: 'courbe')]
    public string $courbe = 'facture';

    public function render()
    {
        $instantanes = IndicateursClinique::derniers(60);
        $dernier = $instantanes[0] ?? null;
        $precedent = $instantanes[1] ?? null;
        $cartes = [];
        if ($dernier) {
            foreach (VueIndicateurs::CARTES as $cle => [$libelle, $chemin, $format, $sens]) {
                $v = VueIndicateurs::lire($dernier['charge'], $chemin);
                $cartes[$cle] = [
                    'libelle' => $libelle,
                    'valeur' => VueIndicateurs::formater($v, $format),
                    'disponible' => $v !== null,
                    'variation' => $precedent ? VueIndicateurs::variation($v, VueIndicateurs::lire($precedent['charge'], $chemin), $format, $sens) : null,
                ];
            }
        }
        $age = $dernier ? max(0, Format::maintenant() - $dernier['recu_le']) : null;
        $seuil = VueIndicateurs::seuilAncien($instantanes);
        $c = $dernier['charge'] ?? [];
        $courbe = array_key_exists($this->courbe, VueIndicateurs::CARTES) ? $this->courbe : 'facture';

        return view('livewire.panneau.tableau-clinique', [
            'jamais' => $dernier === null,
            'cartes' => $cartes,
            'age' => $age,
            'ancien' => $age !== null && $age > $seuil,
            'seuilTexte' => Format::duree($seuil),
            'genereLe' => $dernier['genere_le'] ?? null,
            'recuLe' => $dernier['recu_le'] ?? null,
            'version' => $c['version_application'] ?? null,
            'etatJeu' => $c['etat_jeu'] ?? null,
            'prochaineCode' => VueIndicateurs::lire($c, 'comptabilite.prochaine_echeance_code'),
            'prochaineDate' => VueIndicateurs::lire($c, 'comptabilite.prochaine_echeance_date'),
            'postes' => $c['postes'] ?? [],
            'maintenant' => Format::maintenant(),
            'courbeCle' => $courbe,
            'courbeLibelle' => VueIndicateurs::CARTES[$courbe][0],
            'courbeFormat' => VueIndicateurs::CARTES[$courbe][2],
            'courbeDonnees' => VueIndicateurs::courbe($instantanes, $courbe),
            'choixCourbes' => array_map(fn ($d) => $d[0], VueIndicateurs::CARTES),
            'nbInstantanes' => count($instantanes),
        ]);
    }
}
