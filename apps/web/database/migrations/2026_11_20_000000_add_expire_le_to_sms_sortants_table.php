<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // ADR-0009 (E5204) : durée de validité d'un SMS en attente. Un SMS périmé passe au statut `expire` ; l'instant de l'abandon est gardé, le numéro et le texte sont effacés.
        Schema::table('sms_sortants', function (Blueprint $t) {
            $t->unsignedBigInteger('expire_le')->nullable()->after('echec_le');
        });
    }

    public function down(): void
    {
        Schema::table('sms_sortants', function (Blueprint $t) {
            $t->dropColumn('expire_le');
        });
    }
};
