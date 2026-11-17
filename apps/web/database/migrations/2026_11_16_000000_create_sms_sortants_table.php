<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ADR-0009 : la file des SMS SORTANTS, déposés par la mère déjà composés (un numéro, un texte), envoyés par la tâche planifiée `relais:sms-envoyer`.
        // Le numéro et le texte ne vivent que le temps de l'envoi : ils sont EFFACÉS (NULL) dès que le fournisseur accepte le SMS, ou au cinquième échec.
        // Après effacement, il ne reste que l'identifiant tiré par la mère, le statut, les tentatives, la longueur et des horodatages (ms).
        Schema::create('sms_sortants', function (Blueprint $t) {
            $t->id();
            $t->string('uid', 64)->unique();                        // tiré par la mère : un dépôt rejoué rend la même ligne
            $t->string('numero', 20)->nullable();                   // format international, effacé après envoi
            $t->text('texte')->nullable();                          // déjà composé par la mère, effacé après envoi
            $t->unsignedSmallInteger('longueur');                   // nombre de caractères du texte, gardé pour le journal technique
            $t->string('statut', 16);                               // en_attente | envoye | echec
            $t->unsignedTinyInteger('tentatives')->default(0);
            $t->unsignedBigInteger('depose_le');
            $t->unsignedBigInteger('prochain_essai_le');
            $t->unsignedBigInteger('envoye_le')->nullable();
            $t->unsignedBigInteger('echec_le')->nullable();
            $t->unsignedBigInteger('efface_le')->nullable();
            $t->string('derniere_erreur', 64)->nullable();          // un CODE (http_503, exception…), jamais le corps de la réponse
            $t->index(['statut', 'prochain_essai_le']);
            $t->index('envoye_le');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('sms_sortants');
    }
};
