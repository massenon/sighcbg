<?php
/*
| RENDU STATIQUE DES VUES DU PANNEAU, SANS LARAVEL NI LIVEWIRE. Compile les vrais fichiers Blade avec illuminate/view seulement et les remplit de DONNÉES
| FACTICES (aucun nom de personne, aucune valeur de la clinique). Ce n'est PAS le rendu du relais réel : les composants Livewire (état, polling, Alpine)
| ne s'exécutent pas ; seule la mise en page (HTML + CSS du dépôt) est exercée.
| Usage : RENDU_VENDOR=/chemin/vendor php tests/rendu/rendre.php /dossier/de/sortie
| (le dossier vendor est celui d'un `composer require illuminate/view illuminate/events illuminate/filesystem` fait HORS du dépôt ; il n'est jamais commité).
*/
namespace {
$vendor = getenv('RENDU_VENDOR') ?: '';
if (! is_file($vendor.'/autoload.php')) { fwrite(STDERR, "RENDU_VENDOR doit pointer un dossier vendor contenant illuminate/view\n"); exit(2); }
require $vendor.'/autoload.php';


$racine = dirname(__DIR__, 2);
$sortie = rtrim($argv[1] ?? sys_get_temp_dir().'/rendu', '/');
@mkdir($sortie, 0777, true);
$cache = $sortie.'/_cache'; @mkdir($cache, 0777, true);

// ---- Fonctions globales de Laravel que les vues appellent (versions factices) ----
function env($k, $d = null) { return $d; }
$GLOBALS['conf'] = ['identite' => require dirname(__DIR__, 2).'/config/identite.php', 'relais' => ['mdp_superadmin_min' => 12, 'retention_audit_jours' => 90]];
function config($k) { $p = explode('.', $k); $v = $GLOBALS['conf']; foreach ($p as $s) { $v = $v[$s] ?? null; } return $v; }
function asset($p) { return 'file://'.dirname(__DIR__, 2).'/public/'.$p; }
function route($n, $a = []) { return '#'.$n; }
function csrf_field() { return new \Illuminate\Support\HtmlString('<input type="hidden" name="_token" value="jeton-factice">'); }
function csrf_token() { return 'jeton-factice'; }
function old($k, $d = '') { return $d; }
function auth() { return new class { public function user() { return (object) ['superadmin' => ($GLOBALS['connecte'] ?? true), 'email' => 'admin@exemple.invalid']; } }; }
function request() { return new class { public function routeIs($r) { return $r === ($GLOBALS['route'] ?? ''); } }; }
}
namespace App\Relais {
class Format {
    public static function maintenant(): int { return 1792000000000; }
    public static function date(?int $ms): string { return $ms ? date('d/m/Y H:i', intdiv($ms, 1000)) : 'jamais'; }
    public static function depuis(?int $ms): string { return $ms === null ? 'jamais' : 'il y a '.max(1, intdiv(self::maintenant() - $ms, 60000)).' min'; }
    public static function duree(int $ms): string { return round($ms / 60000).' min'; }
    public static function taille(int $o): string { return number_format($o / 1048576, 1, ',', ' ').' Mo'; }
}
class Surveillance { public static function libelle(string $t): string { return ['battement' => 'Battement de la mère', 'disque' => 'Disque presque plein', 'cron' => 'Cron arrêté'][$t] ?? $t; } }
class VueIndicateurs { public static function formater($v, $f): string { return (string) $v; } }}
namespace App\Relais\Synchro {
class Etat {
    public static function ton(string $e): string { return ['a_jour' => 'ok', 'en_retard' => 'attention', 'silencieux' => 'alerte'][$e] ?? 'attention'; }
    public static function libelle(string $e, ?string $f = null): string { return ['a_jour' => 'À jour', 'en_retard' => 'En retard', 'silencieux' => 'Silencieux', 'revoque' => 'Révoqué'][$e] ?? $e; }
    public static function fonction(?string $p, ?string $f): string { return $p === 'reception' ? 'Réception de secours' : 'Soignant · '.$f; }
}}
namespace App\Livewire\Panneau {
class Alertes { public static function seuil(string $t): string { return '5 min'; } }
class Superadmin { public static function appareil($u): string { return 'Navigateur sur poste'; } public static function adresse($i): string { return '10.xx.xx.4'; } }
}
namespace {
use Illuminate\Container\Container;
use Illuminate\Events\Dispatcher;
use Illuminate\Filesystem\Filesystem;
use Illuminate\Support\HtmlString;
use Illuminate\Support\MessageBag;
use Illuminate\Support\ViewErrorBag;
use Illuminate\View\Compilers\BladeCompiler;
use Illuminate\View\Engines\CompilerEngine;
use Illuminate\View\Engines\EngineResolver;
use Illuminate\View\Factory;
use Illuminate\View\FileViewFinder;

$fichiers = new Filesystem(); $evts = new Dispatcher(new Container());
$compilateur = new BladeCompiler($fichiers, $cache);
$compilateur->directive('livewireStyles', fn () => '');
$compilateur->directive('livewireScripts', fn () => '');
$resolveur = new EngineResolver(); $resolveur->register('blade', fn () => new CompilerEngine($compilateur, $fichiers));
$vues = new Factory($resolveur, new FileViewFinder($fichiers, [$racine.'/resources/views']), $evts);
$vues->share('errors', new ViewErrorBag());

function obj(array $a) { return (object) $a; }
function col(array $l) { return new class($l) implements IteratorAggregate, Countable { public function __construct(private array $l) {} public function getIterator(): Iterator { return new ArrayIterator($this->l); } public function count(): int { return count($this->l); } public function isEmpty(): bool { return $this->l === []; } public function first() { return $this->l[0] ?? null; } }; }
$maintenant = \App\Relais\Format::maintenant();
$min = 60000;
$uuid = fn (int $i) => 'mobile-'.str_pad((string) $i, 4, '0', STR_PAD_LEFT).'-aaaa-bbbb';

// ---- Données factices, par vue ----
$donnees = [
 'tableau' => ['seuilMinutes' => 5, 'age' => 12000, 'alerte' => false, 'actifs' => 7, 'revoques' => 1, 'total' => 1284, 'dernier' => $maintenant - 3 * $min, 'ouvertes' => 1,
   'alertes' => col([obj(['debut' => $maintenant - 90 * $min, 'fin' => $maintenant - 60 * $min, 'type' => 'battement']), obj(['debut' => $maintenant - 20 * $min, 'fin' => null, 'type' => 'disque'])]), 'maintenant' => $maintenant,
   'parSens' => ['journal' => obj(['n' => 900, 'taille' => 5242880]), 'vers_mere' => obj(['n' => 210, 'taille' => 1048576]), 'vers_mobile' => obj(['n' => 174, 'taille' => 733184])],
   'indicateurs' => ['patients_actifs' => 4120, 'factures_du_mois' => 312, 'articles_sous_seuil' => 9]],
 'tableau-clinique' => ['jamais' => false, 'ancien' => false, 'recuLe' => $maintenant - 10 * $min, 'seuilTexte' => '3 h', 'genereLe' => $maintenant - 11 * $min, 'nbInstantanes' => 48, 'prochaineCode' => 'ITS', 'prochaineDate' => '2026-12-10', 'version' => '1.4.2', 'etatJeu' => 'production',
   'cartes' => [
     'patients_actifs' => ['libelle' => 'Patients actifs', 'valeur' => '4 120', 'disponible' => true, 'variation' => ['ton' => 'ok', 'texte' => '+2,1 %']],
     'facture' => ['libelle' => 'Montant facturé du mois', 'valeur' => '18 450 000 FCFA', 'disponible' => true, 'variation' => ['ton' => 'alerte', 'texte' => '−6 %']],
     'occupation' => ['libelle' => 'Taux d’occupation des lits', 'valeur' => 'non disponible', 'disponible' => false, 'variation' => null],
     'sous_seuil' => ['libelle' => 'Articles sous le seuil', 'valeur' => '9', 'disponible' => true, 'variation' => null]],
   'courbe' => 'facture', 'choixCourbes' => ['facture' => 'Montant facturé du mois', 'patients_actifs' => 'Patients actifs'], 'courbeLibelle' => 'Montant facturé du mois', 'courbeFormat' => 'fcfa',
   'courbeDonnees' => ['n' => 5, 'min' => 1, 'max' => 9, 'debut' => $maintenant - 5 * 3600000, 'fin' => $maintenant, 'points' => [['x' => 10, 'y' => 110], ['x' => 150, 'y' => 90], ['x' => 300, 'y' => 60], ['x' => 450, 'y' => 70], ['x' => 590, 'y' => 20]]],
   'postes' => [['appareil' => 'poste-0001-technique', 'derniere_synchro' => $maintenant - 4 * $min], ['appareil' => 'poste-0002-technique', 'derniere_synchro' => 0]]],
 'appareils' => ['message' => 'Appareil révoqué.', 'lignes' => col([
   obj(['uuid' => $uuid(1), 'profil' => 'soignant', 'fonction' => 'infirmier', 'etat' => 'actif', 'dernier' => $maintenant - 2 * $min, 'boite' => 3]),
   obj(['uuid' => $uuid(2), 'profil' => 'reception', 'fonction' => null, 'etat' => 'actif', 'dernier' => $maintenant - 50 * $min, 'boite' => 0]),
   obj(['uuid' => $uuid(3), 'profil' => null, 'fonction' => null, 'etat' => 'revoque', 'dernier' => null, 'boite' => 0])])],
 'boites' => ['boites' => col([obj(['appareil' => $uuid(1), 'vers' => 3, 'depuis' => 41, 'rang' => 44, 'taille' => 262144, 'ancienne' => $maintenant - 30 * $min]), obj(['appareil' => $uuid(2), 'vers' => 0, 'depuis' => 8, 'rang' => 8, 'taille' => 40960, 'ancienne' => $maintenant - 2 * 3600000])]), 'vers' => 3, 'depuis' => 49],
 'codes' => ['valides' => 1, 'utilises' => 4, 'expires' => 2, 'codes' => col([
   obj(['hash' => str_repeat('ab12', 16), 'profil' => 'soignant', 'fonction' => 'sage_femme', 'cree' => $maintenant - 5 * $min, 'expire_le' => $maintenant + 10 * $min, 'utilise' => 0]),
   obj(['hash' => str_repeat('cd34', 16), 'profil' => 'reception', 'fonction' => null, 'cree' => $maintenant - 3 * 3600000, 'expire_le' => $maintenant - 2 * 3600000, 'utilise' => 0]),
   obj(['hash' => str_repeat('ef56', 16), 'profil' => null, 'fonction' => null, 'cree' => null, 'expire_le' => null, 'utilise' => 1])])],
 'indicateurs' => ['dernier' => ['patients_actifs' => 4120, 'version' => '1.4.2'], 'historique' => col([obj(['quand' => $maintenant - $min, 'seq' => 120, 'actifs' => 7, 'conflits' => 0, 'bloques' => 0]), obj(['quand' => $maintenant - 20 * $min, 'seq' => 119, 'actifs' => 6, 'conflits' => 1, 'bloques' => 0])])],
 'synchronisation' => ['mere' => ['etat' => 'a_jour', 'battement' => $maintenant - $min, 'seq' => 120450, 'protocole' => 3], 'reglages' => ['mere_en_retard_min' => 10, 'mere_silencieuse_min' => 30, 'fileul_en_retard_min' => 60, 'fileul_retard_journal' => 500, 'fileul_silencieux_min' => 240, 'mobile_en_retard_min' => 720, 'mobile_silencieux_min' => 2880, 'boite_enveloppes_max' => 200, 'conservation_jours' => 90, 'echantillon_minutes' => 15],
   'mereMuette' => false, 'fileuls' => [['poste' => 'Poste caisse', 'etat' => 'a_jour', 'dernier_contact' => $maintenant - 3 * $min, 'retard_journal' => 0, 'conflits' => 0, 'demandes' => 0], ['poste' => 'Poste accueil', 'etat' => 'silencieux', 'dernier_contact' => null, 'retard_journal' => null, 'conflits' => 2, 'demandes' => 1]],
   'mobiles' => [['uuid' => $uuid(1), 'profil' => 'soignant', 'fonction' => 'infirmier', 'etat' => 'a_jour', 'dernier_depot' => $maintenant - $min, 'dernier_releve' => $maintenant - 2 * $min, 'attente' => 3], ['uuid' => $uuid(2), 'profil' => 'reception', 'fonction' => null, 'etat' => 'en_retard', 'dernier_depot' => null, 'dernier_releve' => null, 'attente' => 120]],
   'total' => 460, 'periodes' => ['24h' => ['Dernières 24 heures'], '7j' => ['7 jours']], 'periode' => '24h', 'natures' => ['tous' => 'Tous', 'mobile' => 'Mobiles', 'fileul' => 'Fileuls'], 'nature' => 'tous',
   'resume' => col([obj(['nature' => 'mobile', 'ref' => $uuid(1), 'releves' => 96, 'silence_max' => 600000, 'retard_max' => 4, 'attente_max' => 12]), obj(['nature' => 'fileul', 'ref' => 'Poste caisse', 'releves' => 96, 'silence_max' => 300000, 'retard_max' => 0, 'attente_max' => null])]),
   'releves' => col([obj(['id' => 1, 'quand' => $maintenant - 5 * $min, 'nature' => 'mobile', 'ref' => $uuid(1), 'dernier_contact' => $maintenant - 7 * $min, 'retard_journal' => 0, 'attente' => 3])])],
 'alertes' => ['message' => 'Courriel de test envoyé.', 'regles' => [['type' => 'battement', 'libelle' => 'Battement de la mère', 'canal' => 'courriel', 'active' => true], ['type' => 'disque', 'libelle' => 'Disque presque plein', 'canal' => 'courriel', 'active' => true], ['type' => 'cron', 'libelle' => 'Cron arrêté', 'canal' => 'courriel', 'active' => false]]],
 'journal' => ['lignes' => col([obj(['quand' => $maintenant - 2 * $min, 'acteur' => 'admin@exemple.invalid', 'action' => 'appareil_revoque', 'detail' => 'uuid=mobile-0003']), obj(['quand' => $maintenant - 3600000, 'acteur' => 'admin@exemple.invalid', 'action' => 'connexion', 'detail' => 'ip=10.xx.xx.4'])])],
 'superadmin' => ['message' => '', 'erreur' => '', 'comptes' => col([obj(['email' => 'admin@exemple.invalid', 'created_at' => \Carbon\Carbon::create(2026, 10, 1), 'derniere' => $maintenant - 30 * $min])]),
   'sessions' => col([obj(['user_agent' => 'x', 'ip_address' => '10.0.0.4', 'last_activity' => intdiv($maintenant, 1000) - 120])]),
   'sms' => ['pilote' => 'essai', 'envoie' => false, 'parametres_manquants' => ['SMS_CLE_API', 'SMS_EXPEDITEUR'], 'envoyes_aujourdhui' => 12, 'plafond_jour' => 200, 'plafond_atteint' => false, 'file' => 3, 'file_en_retard' => 1, 'tentatives_max' => 5, 'echecs' => 0, 'validite_heures' => 24, 'expires' => 1, 'conservation_jours' => 30, 'envoyes' => 88]],
 'opacite' => ['mesure' => ['echantillon' => 20, 'entropie' => 7.998, 'lisibles' => 0], 'cle' => false, 'synchro' => ['lignes' => 460, 'colonnes_hors_liste' => [], 'refs_hors_liste' => 0], 'blocs' => ['entropie' => 7.999, 'echantillon' => 6, 'signatures' => 0, 'lisibles' => 0]],
 'parametres' => ['seuil' => 5, 'secretDefini' => true, 'retention' => 90, 'disque' => 10, 'banc' => false, 'synchroMessage' => '', 'synchroRefus' => [],
   'reglagesSynchro' => ['conservation_jours' => ['libelle' => 'Conservation de l’historique', 'min' => 30, 'max' => 365, 'unite' => 'jours', 'defaut' => 90], 'echantillon_minutes' => ['libelle' => 'Intervalle entre deux relevés', 'min' => 5, 'max' => 60, 'unite' => 'min', 'defaut' => 15]]],
 'sauvegarde' => ['message' => '', 'dernier' => obj(['quand' => $maintenant - 3 * 3600000, 'taille' => 6291456]), 'exports' => col([obj(['quand' => $maintenant - 3 * 3600000, 'taille' => 6291456, 'avant_migration' => 1]), obj(['quand' => $maintenant - 27 * 3600000, 'taille' => 6000000, 'avant_migration' => 0])]),
   'horsSite' => ['utilise' => 734003200, 'quota' => 1073741824, 'pct' => 68.4, 'liberable' => 209715200, 'nb_blocs' => 42, 'limites' => ['rotationPlancher' => 3],
     'copies' => ['magasin' => ['completes' => 2, 'archivees' => 5, 'purgees' => 0, 'derniere' => ['date' => $maintenant - 6 * 3600000, 'taille' => 52428800, 'nb_blocs' => 7]], 'fichiers' => ['completes' => 1, 'archivees' => 2, 'purgees' => 1, 'derniere' => null]]],
   'limitesRefus' => [], 'defauts' => ['quota_mo' => ['libelle' => 'Espace alloué aux copies hors site', 'min' => 100, 'max' => 10000, 'unite' => 'Mo'], 'rotation' => ['libelle' => 'Copies courantes à garder', 'min' => 2, 'max' => 30, 'unite' => 'copies']]],
 'hebergement' => ['php' => '8.3.6', 'base' => 'PostgreSQL', 'cron' => 'il y a 1 min', 'cronEtat' => 'ok', 'disque' => '71 %', 'disqueEtat' => 'attention', 'controles' => [['PHP 8.2 ou plus', 'ok', 'Version 8.3.6'], ['Cron toutes les minutes', 'ok', 'Dernier passage il y a 1 min'], ['Espace disque', 'attention', '71 % occupé'], ['Certificat', 'alerte', 'Expire dans 6 jours']]],
 'consultation' => [],
];
$titres = ['tableau' => ['panneau.tableau', 'Tableau de bord du relais'], 'tableau-clinique' => ['panneau.clinique', ''], 'synchronisation' => ['panneau.synchronisation', ''], 'alertes' => ['panneau.alertes', ''], 'appareils' => ['panneau.appareils', ''], 'boites' => ['panneau.boites', ''], 'codes' => ['panneau.codes', ''],
  'indicateurs' => ['panneau.indicateurs', ''], 'consultation' => ['panneau.consultation', ''], 'journal' => ['panneau.journal', ''], 'superadmin' => ['panneau.superadmin', ''], 'opacite' => ['panneau.opacite', ''], 'parametres' => ['panneau.parametres', ''], 'hebergement' => ['panneau.hebergement', ''], 'sauvegarde' => ['panneau.sauvegarde', '']];

$ecrire = function (string $nom, string $html) use ($sortie) {
    // Le rendu statique n'exécute ni Alpine ni Livewire : les blocs conditionnels d'Alpine (x-show) sont masqués comme Alpine le ferait au chargement, sans plus.
    $script = "<script>document.querySelectorAll('[x-show]').forEach(function(e){e.style.display='none'});</script></body>";
    file_put_contents($sortie.'/'.$nom.'.html', str_replace('</body>', $script, $html));
};
foreach ($titres as $nom => [$route]) {
    $GLOBALS['route'] = $route;
    $corps = $vues->make('livewire.panneau.'.$nom, $donnees[$nom])->render();
    $ecrire($nom, $vues->make('layouts.panneau', ['slot' => new HtmlString($corps)])->render());
}
$GLOBALS['route'] = '';
$ecrire('connexion', $vues->make('panneau.connexion')->render());
$q = ['titre' => 'Questionnaire de satisfaction', 'clinique' => 'CLINIQUE BAGUIDI', 'description' => 'Votre avis nous aide à nous améliorer.', 'champs' => [
  ['nom' => 'accueil', 'libelle' => 'Comment jugez-vous l’accueil ?', 'type' => 'select', 'requis' => true, 'options' => ['Très bien', 'Bien', 'Moyen', 'Insuffisant'], 'lignes' => 0],
  ['nom' => 'attente', 'libelle' => 'Le temps d’attente vous a-t-il paru raisonnable ?', 'type' => 'select', 'requis' => true, 'options' => ['Oui', 'Non'], 'lignes' => 0],
  ['nom' => 'commentaire', 'libelle' => 'Un commentaire ?', 'type' => 'texte', 'requis' => false, 'options' => [], 'lignes' => 4]]];
$html = $vues->make('satisfaction.questionnaire', ['d' => $q])->render();
// La page publique montre son formulaire une fois son script exécuté : on le dévoile pour la capture.
$html = str_replace(['<form id="sat-formulaire" hidden novalidate>', '<p id="sat-sans-js" class="etat erreur">'], ['<form id="sat-formulaire" novalidate>', '<p id="sat-sans-js" class="etat erreur" hidden>'], $html);
file_put_contents($sortie.'/satisfaction.html', $html);
file_put_contents($sortie.'/satisfaction-invalide.html', $vues->make('satisfaction.invalide')->render());
echo count(glob($sortie.'/*.html'))." pages écrites dans $sortie\n";
}
