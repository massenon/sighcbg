<?php

namespace Tests\Unit;

use PHPUnit\Framework\TestCase;

/*
| Garde du design du panneau : AUCUNE couleur en dur et AUCUNE ressource externe dans les vues et feuilles du panneau, de la connexion et de la page publique de
| satisfaction. Les couleurs vivent dans public/css/jetons.css (engendré depuis docs/design/design-tokens.json par tools/baguidi/engendrer-jetons-relais.mjs).
| Le contrôle de contraste et celui de la fraîcheur de jetons.css sont dans tests/js/panneau-jetons.test.mjs (node --test).
*/
class PanneauSansEnDurTest extends TestCase
{
    /** @return list<string> */
    private function fichiers(): array
    {
        $racine = dirname(__DIR__, 2);
        $f = [$racine.'/public/css/panneau.css', $racine.'/public/css/satisfaction.css'];
        foreach (['layouts', 'livewire/panneau', 'panneau', 'satisfaction'] as $d) {
            $it = new \RecursiveIteratorIterator(new \RecursiveDirectoryIterator($racine.'/resources/views/'.$d, \FilesystemIterator::SKIP_DOTS));
            foreach ($it as $x) {
                $f[] = $x->getPathname();
            }
        }

        return $f;
    }

    private function sansCommentaires(string $t): string
    {
        return (string) preg_replace(['/\{\{--.*?--\}\}/s', '#/\*.*?\*/#s'], '', $t);
    }

    public function test_aucune_couleur_en_dur(): void
    {
        $fautes = [];
        foreach ($this->fichiers() as $f) {
            $t = $this->sansCommentaires((string) file_get_contents($f));
            if (preg_match_all('/#(?:[0-9a-fA-F]{8}|[0-9a-fA-F]{6}|[0-9a-fA-F]{3,4})(?![0-9a-zA-Z_-])|\b(?:rgba?|hsla?|oklch|hwb)\(/', $t, $m)) {
                $fautes[] = basename($f).' : '.implode(', ', $m[0]);
            }
        }
        $this->assertSame([], $fautes, 'couleur en dur : utiliser var(--…) de jetons.css');
    }

    public function test_aucune_url_externe(): void
    {
        $fautes = [];
        foreach ($this->fichiers() as $f) {
            $t = $this->sansCommentaires((string) file_get_contents($f));
            if (preg_match_all('#(?:https?:)?//[a-z0-9.-]+\.[a-z]{2,}|fonts\.googleapis|cdn\.#i', $t, $m)) {
                $fautes[] = basename($f).' : '.implode(', ', $m[0]);
            }
        }
        $this->assertSame([], $fautes, 'ressource externe : le relais ne charge rien hors de lui-même');
    }
}
