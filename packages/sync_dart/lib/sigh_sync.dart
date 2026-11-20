/// Moteur de synchronisation SIGH-CBG (repris de SIGH-CBG) : poste mère, poste fileul, mobile.
library;

export 'src/commun.dart' show arg, uuid7, Err;
export 'src/mere.dart' show Mere, ConfigMere;
export 'src/fileul.dart' show Fileul, ConfigFileul;
export 'src/mobile.dart' show Mobile, ConfigMobile;
export 'src/pair.dart' show FileulPair, ConfigPair;
export 'src/smtp.dart' show ConfigSmtp, EtapeSmtp, ResultatSmtp, envoyerSmtp;
export 'src/fichiers.dart' show StockFichiers, ClientFichiers, ScelleFichiers, AppelMere, tailleBloc;
// La sauvegarde hors site (lot BAK, ADR-0008) : blocs opaques chiffrés par la clé de la clinique, relais web ou dossier distant monté, restauration vérifiée avant d'écrire.
export 'src/sauvegarde_horssite.dart'
    show
        ErreurSauvegarde,
        BlocScelle,
        ChiffreurSauvegarde,
        DestinationSauvegarde,
        DestinationRelais,
        DestinationDossier,
        ElementASauver,
        ElementIllisible,
        IndexBlocs,
        ResultatDepot,
        ResultatRestauration,
        sauvegarderHorsSite,
        restaurerHorsSite,
        controlerHorsSite;

// L'export complet portable (décision 12, 17/11/2026) : un fichier, un manifeste lisible sans clé, un contenu chiffré par la clé de la clinique, vérifiable sans écrire.
export 'src/export_portable.dart' show ContenuExport, ExportPortable, RapportVerification, RapportImportMere, extraireMere, importerMereDansCibleNeuve, gardeSchemaDepot, tablesDuDepot;
