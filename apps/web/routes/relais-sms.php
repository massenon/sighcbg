<?php

use App\Http\Controllers\SmsController;
use Illuminate\Support\Facades\Route;

/*
| ADR-0009 : les SMS par le relais (contrat : packages/sync/banc/relais-sms.js). Réservées à la mère : secret `x-mere` + signature du corps.
*/
Route::post('/mere/sms', [SmsController::class, 'deposer']);
Route::post('/mere/sms/statuts', [SmsController::class, 'statuts']);
Route::get('/mere/sms/etat', [SmsController::class, 'etat']);

Route::post('/banc/sms/tourner', [SmsController::class, 'bancTourner']);
Route::get('/banc/sms/tout', [SmsController::class, 'bancTout']);
