<?php

namespace Tests\Unit;

use App\Relais\IndicateursClinique;
use PHPUnit\Framework\TestCase;

/** Le schéma FERMÉ des indicateurs agrégés (ADR-0007), sans base ni réseau. */
class IndicateursCliniqueSchemaTest extends TestCase
{
    private const EXEMPLE = __DIR__.'/../../../../packages/schema/indicateurs-clinique.exemple.json';

    public function test_l_exemple_partage_avec_le_calculateur_du_poste_est_conforme(): void
    {
        if (! is_file(self::EXEMPLE)) {
            $this->markTestSkipped('packages/schema absent de cette copie du dépôt.');
        }
        $exemple = json_decode((string) file_get_contents(self::EXEMPLE), true);
        $this->assertSame([], IndicateursClinique::valider($exemple));
    }

    public function test_chaque_champ_du_calculateur_est_obligatoire_et_aucun_n_est_en_trop(): void
    {
        if (! is_file(self::EXEMPLE)) {
            $this->markTestSkipped('packages/schema absent de cette copie du dépôt.');
        }
        $exemple = json_decode((string) file_get_contents(self::EXEMPLE), true);
        foreach ($this->chemins($exemple) as $chemin) {
            $copie = $exemple;
            $this->retirer($copie, explode('.', $chemin));
            $this->assertNotSame([], IndicateursClinique::valider($copie), "« $chemin » devrait être obligatoire");
        }
        $this->assertContains('postes[]', array_map(fn ($c) => preg_replace('/\.[^.]+$/', '', $c), array_filter($this->chemins($exemple), fn ($c) => str_contains($c, '[]'))));
    }

    public function test_les_messages_de_refus_nomment_des_chemins_jamais_une_valeur(): void
    {
        $i = json_decode((string) file_get_contents(self::EXEMPLE), true);
        $i['patients']['actifs'] = 'ZANTCHEDE Kadidja';
        $i['nom'] = 'VODOUHE Fiacre';
        $texte = implode(' | ', IndicateursClinique::valider($i));
        $this->assertStringContainsString('patients.actifs', $texte);
        $this->assertStringNotContainsString('Kadidja', $texte);
        $this->assertStringContainsString('nom : champ inattendu', $texte);
        $this->assertStringNotContainsString('Fiacre', $texte);
    }

    public function test_un_nom_de_champ_inattendu_est_tronque_dans_le_message(): void
    {
        $i = json_decode((string) file_get_contents(self::EXEMPLE), true);
        $i[str_repeat('x', 500)] = 1;
        foreach (IndicateursClinique::valider($i) as $d) {
            $this->assertLessThan(120, strlen($d));
        }
    }

    public function test_les_types_stricts(): void
    {
        $base = json_decode((string) file_get_contents(self::EXEMPLE), true);
        foreach ([[1.0, false], [1.5, false], ['1', false], [true, false], [[], false], [0, true], [null, true]] as [$valeur, $ok]) {
            $i = $base;
            $i['patients']['actifs'] = $valeur;
            $this->assertSame($ok, IndicateursClinique::valider($i) === [], var_export($valeur, true));
        }
        $this->assertNotSame([], IndicateursClinique::valider('texte'));
        $this->assertNotSame([], IndicateursClinique::valider(null));
        $this->assertNotSame([], IndicateursClinique::valider([1, 2, 3]));
    }

    private function chemins(array $n, string $prefixe = ''): array
    {
        $sortie = [];
        foreach ($n as $k => $v) {
            if (is_array($v) && array_is_list($v) && $v !== [] && is_array($v[0])) {
                foreach ($this->chemins($v[0], ($prefixe === '' ? '' : $prefixe.'.').$k.'[]') as $c) {
                    $sortie[] = $c;
                }
            } elseif (is_array($v)) {
                foreach ($this->chemins($v, ($prefixe === '' ? '' : $prefixe.'.').$k) as $c) {
                    $sortie[] = $c;
                }
            } else {
                $sortie[] = ($prefixe === '' ? '' : $prefixe.'.').$k;
            }
        }

        return $sortie;
    }

    private function retirer(array &$a, array $chemin): void
    {
        $k = array_shift($chemin);
        if (str_ends_with($k, '[]')) {
            $k = substr($k, 0, -2);
            foreach ($a[$k] as &$e) {
                $this->retirer($e, $chemin);
            }

            return;
        }
        if ($chemin === []) {
            unset($a[$k]);

            return;
        }
        $this->retirer($a[$k], $chemin);
    }
}
