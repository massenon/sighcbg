<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Instantanés d'indicateurs AGRÉGÉS publiés par la mère (ADR-0007) : des nombres, des dates, un code d'obligation, un numéro de version,
        // des identifiants techniques d'appareils. JAMAIS un nom, un code patient, un libellé libre : la validation les refuse avant l'écriture.
        // Conservation bornée : le relais ne garde que les N derniers (config relais.indicateurs_clinique_max).
        Schema::create('indicateurs_clinique', function (Blueprint $t) {
            $t->id();
            $t->unsignedBigInteger('recu_le');                // ms, horloge du relais
            $t->unsignedBigInteger('genere_le')->unique();    // ms, horloge de la mère : un instantané rejoué est refusé
            $t->unsignedSmallInteger('version_schema');
            $t->text('charge');                               // l'instantané validé, en JSON
            $t->index('recu_le');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('indicateurs_clinique');
    }
};
