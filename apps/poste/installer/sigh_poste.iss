; =============================================================================
;  SIGH-CBG Poste : installateur Windows (Inno Setup 6), Clinique Baguidi
;
;  Compile par build_windows.bat, qui passe la version lue dans pubspec.yaml :
;      ISCC.exe /DAppVersion=0.1.0 installer\sigh_poste.iss
;  Produit : build\installer\SIGH_Poste_Setup_<version>.exe
;
;  Installe TOUT le dossier de sortie de `flutter build windows --release`
;  (build\windows\x64\runner\Release\) dans {autopf}\SIGH-CBG. Droits
;  administrateur (decision de la Direction, 05/11/2026, Q3).
;
;  Les DONNEES ne sont JAMAIS dans le dossier d'installation :
;    %LOCALAPPDATA%\SIGHCBG\donnees  (base, magasin, cle de chiffrement, sauvegardes de la mere)
;  (lib/core/dossier_donnees.dart). Une MISE A JOUR (meme AppId) n'y touche jamais.
;
;  DESINSTALLATION (decision de la Direction, 05/11/2026, Q1) :
;    1. une sauvegarde est proposee d'abord (Documents\SIGH-CBG-Sauvegarde-AAAA-MM-JJ_HHMM,
;       jamais supprimee par le desinstallateur) ;
;    2. un avertissement Oui / Non, « Non » par defaut ; Non ANNULE la desinstallation ;
;    3. les donnees ne sont supprimees que sur « Oui » ;
;    4. en mode silencieux (/SILENT, /VERYSILENT), les donnees sont GARDEES.
;  Les exports faits par l'utilisateur (dossier Telechargements) ne sont pas touches.
; =============================================================================

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif

#define AppName "SIGH-CBG Poste"
#define AppPublisher "Clinique Baguidi L'As de Coeur"
#define AppExeName "sigh_poste.exe"
#define SetupBaseName "SIGH_Poste_Setup"
#define SourceDir AddBackslash(SourcePath) + "..\build\windows\x64\runner\Release"
#define IconFile AddBackslash(SourcePath) + "..\windows\runner\resources\app_icon.ico"

#if !FileExists(SourceDir + "\" + AppExeName)
  #error "Executable absent : lancez d'abord flutter build windows --release (build_windows.bat le fait)."
#endif

[Setup]
; Identifiant FIXE de l'application : NE JAMAIS LE CHANGER. C'est lui qui fait
; qu'une nouvelle version REMPLACE l'ancienne au lieu de s'installer a cote.
; Celui de SIGH-CBG est PROPRE a la Clinique Baguidi (06/11/2026, PRD P0-7) et
; differe de celui de SIGH-CBG : les deux logiciels cohabitent sur une machine.
AppId={{8DE5823E-F0D2-40FD-A337-280D6E5BF4D5}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoProductName={#AppName}
DefaultDirName={autopf}\SIGH-CBG
DefaultGroupName=SIGH-CBG
DisableProgramGroupPage=yes
OutputDir=..\build\installer
OutputBaseFilename={#SetupBaseName}_{#AppVersion}
#if FileExists(IconFile)
SetupIconFile={#IconFile}
#endif
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; Flutter Windows ne produit que du x64.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
; Une mise a jour ferme l'application ouverte avant de remplacer ses fichiers.
CloseApplications=yes
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Seulement si l'utilisateur a repondu Oui a l'avertissement (SupprimerLesDonnees, pose par InitializeUninstall).
Type: filesandordirs; Name: "{localappdata}\SIGHCBG"; Check: SupprimerLesDonnees

[Code]
var
  SupprimerDonnees: Boolean;

// ---------------------------------------------------------------------------
// SAUVEGARDE OBLIGATOIRE AVANT UNE MISE A JOUR (decision 12, 17/11/2026).
// Une MISE A JOUR (donnees deja presentes) ne s'installe que si le poste a
// ecrit une AUTORISATION recente : « Preparer la mise a jour » (sauvegarde
// verifiee ET export portable verifie de moins de N heures, N = reglage date
// `maj.sauvegardeMaxHeures`). Le fichier est `autorisation-mise-a-jour.txt`
// dans le dossier des donnees (cles `cle=valeur`, dates locales AAAAMMJJHHMMSS,
// meme format que `majTexteAutorisation` du domaine). Une premiere
// installation (aucune donnee) passe sans condition. Le blocage ne se leve que
// dans l'application, par le geste reserve « Lever le blocage d'une mise a
// jour » (motif ecrit, journalise). LIMITE ASSUMEE : le fichier protege contre
// l'OUBLI ; un administrateur de la machine peut le contourner en connaissance
// de cause.
// ---------------------------------------------------------------------------
function DossierDonnees(): String;
begin
  Result := ExpandConstant('{localappdata}\SIGHCBG\donnees');
end;

function DonneesPresentes(): Boolean;
begin
  Result := DirExists(DossierDonnees() + '\magasin') or FileExists(DossierDonnees() + '\mere.db');
end;

// La valeur d'une cle `cle=valeur` dans les lignes du fichier ; vide si absente.
function ValeurDe(const Lignes: TArrayOfString; const Cle: String): String;
var
  I: Integer;
  Prefixe: String;
begin
  Result := '';
  Prefixe := Cle + '=';
  for I := 0 to GetArrayLength(Lignes) - 1 do
    if Copy(Lignes[I], 1, Length(Prefixe)) = Prefixe then
    begin
      Result := Trim(Copy(Lignes[I], Length(Prefixe) + 1, Length(Lignes[I])));
      Exit;
    end;
end;

// Vide si l'installation est autorisee ; sinon le code du refus, nomme (memes codes que le domaine).
function RefusMiseAJour(): String;
var
  Lignes: TArrayOfString;
  Jusqu, Maintenant: String;
begin
  Result := '';
  if not DonneesPresentes() then
    Exit;
  if not LoadStringsFromFile(DossierDonnees() + '\autorisation-mise-a-jour.txt', Lignes) then
  begin
    Result := 'AUTORISATION_ABSENTE';
    Exit;
  end;
  if (GetArrayLength(Lignes) = 0) or (Copy(Lignes[0], 1, 21) <> 'SIGH-AUTORISATION-MAJ') then
  begin
    Result := 'AUTORISATION_ILLISIBLE';
    Exit;
  end;
  Jusqu := ValeurDe(Lignes, 'valable_jusqu_local');
  if Length(Jusqu) <> 14 then
  begin
    Result := 'AUTORISATION_ILLISIBLE';
    Exit;
  end;
  Maintenant := GetDateTimeString('yyyymmddhhnnss', #0, #0);
  if CompareStr(Jusqu, Maintenant) < 0 then
    Result := 'AUTORISATION_EXPIREE';
end;

function InitializeSetup(): Boolean;
var
  Refus: String;
begin
  Result := True;
  Refus := RefusMiseAJour();
  if Refus <> '' then
  begin
    MsgBox(
      'Mise a jour BLOQUEE : ' + Refus + #13#10 + #13#10 +
      'Avant de mettre a jour, ouvrez SIGH-CBG, onglet Parametres, « Export, import et mise a jour », puis « Preparer la mise a jour » : une sauvegarde verifiee et un export portable de moins de quelques heures sont exiges (le delai est un reglage de la clinique).' + #13#10 + #13#10 +
      'En cas de force majeure, un administrateur peut lever le blocage depuis l''application (geste reserve, motif ecrit et journalise).',
      mbError, MB_OK);
    Result := False;
  end;
end;

// Une autorisation vaut pour UNE mise a jour : elle est retiree une fois l'installation faite.
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    DeleteFile(DossierDonnees() + '\autorisation-mise-a-jour.txt');
end;

function SupprimerLesDonnees(): Boolean;
begin
  Result := SupprimerDonnees;
end;

// Copie un dossier (sous-dossiers compris) ; un dossier source absent n'est pas une erreur (rien a sauvegarder).
function CopierDossier(Source, Cible: String): Boolean;
var
  Code: Integer;
begin
  if not DirExists(Source) then
  begin
    Result := True;
    Exit;
  end;
  Result := Exec(ExpandConstant('{cmd}'),
    '/C xcopy "' + Source + '" "' + Cible + '\" /E /I /H /Y /Q', '', SW_HIDE, ewWaitUntilTerminated, Code)
    and (Code = 0);
end;

// Le poste est ferme d'abord (une base ouverte ne se copie pas de facon coherente), puis copie horodatee dans Documents.
function SauvegarderAvantSuppression(var Dossier: String): Boolean;
var
  Code: Integer;
begin
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#AppExeName}', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Dossier := ExpandConstant('{userdocs}\SIGH-CBG-Sauvegarde-') + GetDateTimeString('yyyy/mm/dd_hhnn', '-', #0);
  Result := ForceDirectories(Dossier)
    and CopierDossier(ExpandConstant('{localappdata}\SIGHCBG'), Dossier + '\donnees-du-poste');
end;

// Sauvegarde proposee (Oui par defaut), puis avertissement Oui / Non (Non par defaut). Non ANNULE la desinstallation.
function InitializeUninstall(): Boolean;
var
  Dossier: String;
begin
  Result := True;
  SupprimerDonnees := False;
  // Silencieux : aucune question possible, donc aucune suppression.
  if UninstallSilent then
    Exit;

  if MsgBox(
    'Voulez-vous faire une SAUVEGARDE de ce poste avant de continuer ?' + #13#10 + #13#10 +
    'Elle sera enregistree dans votre dossier Documents (SIGH-CBG-Sauvegarde-...) et ne sera pas supprimee.',
    mbConfirmation, MB_YESNO or MB_DEFBUTTON1) = IDYES then
  begin
    if SauvegarderAvantSuppression(Dossier) then
      MsgBox('Sauvegarde terminee :' + #13#10 + Dossier, mbInformation, MB_OK)
    else if MsgBox(
      'La sauvegarde a echoue (espace disque ou acces refuse).' + #13#10 + #13#10 +
      'Continuer QUAND MEME vers la desinstallation ?',
      mbError, MB_YESNO or MB_DEFBUTTON2) <> IDYES then
    begin
      Result := False;
      Exit;
    end;
  end;

  if MsgBox(
    'Desinstaller {#AppName} supprimera aussi TOUTES les donnees de ce poste :' + #13#10 +
    '  - la base locale (comptes, patients, factures, stocks, comptabilite...)' + #13#10 +
    '  - la cle de chiffrement du poste' + #13#10 +
    '  - la configuration du poste (mode, appairage, adresse de la mere)' + #13#10 +
    '  - les sauvegardes de la mere stockees dans ce dossier' + #13#10 + #13#10 +
    'Les saisies NON ENCORE SYNCHRONISEES seront PERDUES, definitivement. ' +
    'Sur un poste MERE, cette base est la copie de reference de la clinique : les postes fileuls ne la reconstituent pas entierement.' + #13#10 + #13#10 +
    'Cette action est irreversible. Voulez-vous desinstaller et supprimer ces donnees ?' + #13#10 + #13#10 +
    'Oui : tout supprimer.     Non : annuler la desinstallation.',
    mbError, MB_YESNO or MB_DEFBUTTON2) = IDYES then
    SupprimerDonnees := True
  else
    Result := False;
end;
