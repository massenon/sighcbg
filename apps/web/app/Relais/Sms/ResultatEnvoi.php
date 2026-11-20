<?php

namespace App\Relais\Sms;

/** La réponse d'un pilote : accepté ou non, et un CODE technique (jamais le corps de la réponse du fournisseur, qui pourrait répéter le texte). */
final class ResultatEnvoi
{
    public function __construct(public readonly bool $accepte, public readonly string $code = 'ok')
    {
    }

    public static function accepte(): self
    {
        return new self(true, 'ok');
    }

    public static function refuse(string $code): self
    {
        return new self(false, substr(preg_replace('/[^a-z0-9_]/', '_', strtolower($code)) ?: 'inconnu', 0, 64));
    }
}
