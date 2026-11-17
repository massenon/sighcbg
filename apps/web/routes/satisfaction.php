<?php

use App\Http\Controllers\SatisfactionController;
use Illuminate\Support\Facades\Route;

/*
| SATISFACTION EN LIGNE (décision de la Direction du 16/11/2026, section 8). Contrat : packages/sync/banc/relais-satisfaction.js.
| Chargé par routes/relais.php : sans session ni CSRF (la page publique n'a ni cookie ni formulaire classique ; le dépôt est un JSON chiffré).
| Routes PUBLIQUES limitées en débit par adresse (table cache, aucune adresse stockée avec une réponse) ; routes de la MÈRE signées.
*/
Route::get('/satisfaction/{jeton}', [SatisfactionController::class, 'page'])
    ->middleware('throttle:'.config('satisfaction.debit_page_par_minute', 60).',1,satisfaction-page');
Route::get('/satisfaction/{jeton}/modele', [SatisfactionController::class, 'modele'])
    ->middleware('throttle:'.config('satisfaction.debit_page_par_minute', 60).',1,satisfaction-page');
Route::post('/satisfaction/{jeton}/reponse', [SatisfactionController::class, 'deposer'])
    ->middleware('throttle:'.config('satisfaction.debit_depot_par_minute', 10).',1,satisfaction-depot');

Route::post('/mere/satisfaction/publier', [SatisfactionController::class, 'publier']);
Route::post('/mere/satisfaction/revoquer', [SatisfactionController::class, 'revoquer']);
Route::post('/mere/satisfaction/relever', [SatisfactionController::class, 'relever']);
Route::post('/mere/satisfaction/acquitter', [SatisfactionController::class, 'acquitter']);

Route::get('/banc/satisfaction/tout', [SatisfactionController::class, 'bancTout']);
Route::post('/banc/satisfaction/vieillir', [SatisfactionController::class, 'bancVieillir']);
