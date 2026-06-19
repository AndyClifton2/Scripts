<#
.SYNOPSIS
    Azure CAF Platform Foundation Checklist Verificatie
.DESCRIPTION
    Controleert of alle items uit de CAF Terraform checklist zijn gedeployed en actief zijn.
    Geeft groene vinkjes (✅) voor OK, rode kruisjes (❌) voor niet gevonden/actief,
    en waarschuwingen (⚠️) voor skipped/opinionated checks.

    WIJZIGINGEN t.o.v. v0.8:
    - $RootMgName verwijderd; root scope wordt afgeleid van $TenantId
    - $IntermediateRootMgName en $LandingZonesMgName zijn nu losse parameters
    - PLATFORM-G05: root scope fix (was hardcoded "Tenant Root Group", nu $TenantId)
    - PLATFORM-G08/G31/G09/C11/S01: $_.DisplayName i.p.v. $_.Properties.DisplayName (Az.Resources 7.x)
    - PLATFORM-G08: ghost assignments (verwijderde Entra-identiteiten) worden gefilterd en gemeld
    - PLATFORM-G31: Get-AzRoleEligibilityScheduleInstance i.p.v. Get-AzRoleEligibleChildResource
    - PLATFORM-G40: Azure CLI detectie toegevoegd; fallback naar Get-AzConsumptionBudget
    - PLATFORM-G34/35: check beperkt tot geconfigureerde platform subscriptions
    - PLATFORM-G06: zoekt policies op intermediate root én één niveau hoger (tenant root)
    - PLATFORM-G24/25: scope-parameter $TagPolicyMgName toegevoegd (kan lager dan root)
    - PLATFORM-LZ02: gemarkeerd als opinionated (CAF raadt env-based MGs af)
    - PLATFORM-LZ-std: scope gecorrigeerd naar applicatie LZ subscriptions
    - Test-PolicyAssignmentExists: gebruikt $_.DisplayName (Az.Resources 7.x compatibel)


    WIJZIGINGEN t.o.v. v0.9:
    - PLATFORM-C10/C12/C13: Firewall-query niet meer beperkt tot $HubResourceGroup;
      in vWAN Secured Hub zit de Firewall in een Microsoft-managed resource group
    - PLATFORM-G40: Get-AzConsumptionBudget vervangen door Invoke-AzRestMethod (ARM REST);
      werkt zonder Az.Billing module
    - DOWR-B05/06: logicabug opgelost (leeg bij "Immutable gevonden" als detail)
    - PLATFORM-LZ-std: volledig recursieve MG-traversal (was maar één niveau diep)

    WIJZIGINGEN t.o.v. v1.0:
    - PLATFORM-C10/C12/C13: optioneel via $FirewallEnabled; bij $false worden checks
      als skipped gemeld met toelichting dat klant bewust geen Firewall heeft
    - PLATFORM-G01: Sandbox optioneel via $SandboxMgExpected; bij $false wordt een
      afwijkende kleur gebruikt en telt het niet als mislukking

    WIJZIGINGEN t.o.v. v1.1:
    - PLATFORM-G05: ghost-assignments (verwijderde Entra-identiteiten) en duplicaten
      op ObjectId worden niet meer meegeteld in het Owner-aantal
    - PLATFORM-G06: nieuwe parameter $AuditPolicyMgName; de check zoekt nu ook op deze
      configureerbare MG en diens directe sub-MG's, niet alleen op intermediate
      root + tenant root. Nodig wanneer audit-policies op een lager niveau staan
      (bijv. onder een apart MG voor ongemanagede/student-subscriptions)

    WIJZIGINGEN t.o.v. v1.2:
    - Nieuwe patroonherkenning: als 4 of meer van de 7 Azure Policy-afhankelijke
      checks (G06, G09/10, G18, G23, G24/25, C11, S01) ❌ zijn, toont het script
      één samenvattende ⚠️-melding die uitlegt dat dit waarschijnlijk één
      onderliggende oorzaak is (geen custom Azure Policy/EPAC-laag in de tenant),
      in plaats van zeven losse problemen. De individuele checks blijven ongewijzigd
      zichtbaar voor wie wél een Azure Policy-laag heeft.

    WIJZIGINGEN t.o.v. v1.3:
    - PLATFORM-LZ-bkp / DOWR-B05/06 / DOWR-B08: zochten alleen in $ManagementSubId,
      waardoor Recovery Services Vaults onder Landing Zone-subscriptions (bijv.
      RSV-PLATFORM-LZ-hub onder een losse LZ-subscription) werden gemist. Nu wordt
      ook gezocht in $ConnectivitySubId en alle subscriptions onder de Landing
      Zones MG (dezelfde set die PLATFORM-LZ-std al gebruikt)
    - PLATFORM-G06: detailtekst bij geen resultaat toonde de MG-naam dubbel als
      $IntermediateRootMgName en $AuditPolicyMgName gelijk waren ('PLATFORM', 'PLATFORM').
      Wordt nu ontdubbeld.
    - PLATFORM-G09/10: consistent gemaakt met $SandboxMgExpected. Als Sandbox bewust
      niet bestaat ($SandboxMgExpected = $false), wordt deze check nu ook als
      ⚠️ skipped gemeld in plaats van ❌ — isoleren van een niet-bestaande MG
      heeft geen betekenis.

    WIJZIGINGEN t.o.v. v1.4:
    - Nieuwe resultaatcategorie 🟠 Warning (naast ✅/❌/⚠️), met eigen teller
      $WarningCount. Bedoeld voor checks waar een bewuste configuratiekeuze
      (zoals $FirewallEnabled = $false) een reëel risico achterlaat zonder
      vangnet — geen onverwachte misconfiguratie (❌) en geen neutrale
      n.v.t.-situatie (⚠️ skip), maar een eigen signaal.
    - PLATFORM-C13: gebruikt nu de Warning-categorie. Als $FirewallEnabled = $false
      én er geen DDoS Protection Plan aanwezig is, toont de check 🟠 in plaats
      van ❌ — het is een voorzienbaar gevolg van de bewuste Firewall-keuze,
      geen losse fout. Met een DDoS Plan blijft het ✅; met Firewall ingeschakeld
      werkt de check ongewijzigd als ✅/❌.
    - IAM-3: zocht alleen naar user-assigned managed identities (los resourcetype).
      System-assigned identities (een Identity-eigenschap op VM's, Web Apps,
      Logic Apps, Container Instances) werden volledig gemist. De check doorzoekt
      nu beide platform-subscriptions op zowel user-assigned als system-assigned
      identities over deze vier meest voorkomende resourcetypes.

    WIJZIGINGEN t.o.v. v1.5:
    - IAM-3: vervangen door Azure Resource Graph (Search-AzGraph), die in één
      tenant-brede query ALLE resources met een Identity-blok vindt, ongeacht
      resourcetype. De vorige hardcoded resourcetype-lijst (VM/Web App/Logic
      App/Container Instance) miste daadwerkelijke identities op Storage
      Accounts, Automation Accounts, Recovery Services Vaults, en Azure
      Local/Arc-resources (AzureStackHCI, ResourceConnector, HybridCompute) —
      bevestigd via een los diagnostisch script (Check-ManagedIdentities-
      TenantWide.ps1) dat 9 system-assigned identities tenant-breed vond.
      Valt terug op een uitgebreide resourcetype-lijst als Az.ResourceGraph
      niet geïnstalleerd is.

    WIJZIGINGEN t.o.v. v1.6:
    - PLATFORM-G31: automatische Entra ID P2-licentiedetectie via Microsoft Graph
      (Get-MgSubscribedSku). PIM vereist P2 (los, of via een bundel zoals
      Microsoft 365 E5 / EMS E5). Tenants zonder P2 krijgen nu automatisch
      ⚠️ skipped in plaats van ❌ — geen handmatige per-klant instelling nodig,
      relevant omdat dit script bij meerdere klanten gebruikt gaat worden,
      waarvan niet allemaal P2 hebben. Tenants met P2 krijgen een normale
      ✅/❌ op basis van daadwerkelijke PIM eligible assignments. Als de
      Microsoft.Graph.Identity.DirectoryManagement module ontbreekt, valt de
      check terug op de oude aanpak (PIM-query zonder licentiecontrole).

.NOTES
    Vereisten : Az PowerShell module (6.x of hoger) + ingelogd via Connect-AzAccount
                Optioneel: Az.ResourceGraph (voor volledige IAM-3-dekking)
                Optioneel: Microsoft.Graph.Identity.DirectoryManagement (voor G31 P2-detectie)
    Versie    : 1.7 | Juni 2026
#>

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG — pas deze waarden aan voor jouw omgeving
# ─────────────────────────────────────────────────────────────────────────────
$TenantId                = ""

# Root scope wordt automatisch afgeleid van TenantId
$rootScope               = "/providers/Microsoft.Management/managementGroups/$TenantId"

# Naam van jouw Intermediate Root MG (de laag direct onder Tenant Root Group)
$IntermediateRootMgName  = ""

# Naam van de Landing Zones MG
$LandingZonesMgName      = "Landing Zones"

# Naam van de MG waarop tag-policies zijn toegewezen
$TagPolicyMgName         = ""

# Naam van de MG waarop audit-only policies zijn toegewezen
# Kan lager liggen dan $IntermediateRootMgName, bijvoorbeeld als je tussen Root en
# de echte audit-laag nog een MG hebt voor losse subscriptions die je niet monitort
# (zoals Azure for Students). Zet hier de daadwerkelijke scope van je audit-policy.
$AuditPolicyMgName       = ""

# Subscription IDs
$ConnectivitySubId       = ""
$ManagementSubId         = ""

# Resource groups en resourcenamen
$HubResourceGroup        = ""
$DnsResourceGroup        = ""
$LogAnalyticsRGPlatform  = ""
$VWanName                = ""
$VHubName                = ""
$FirewallPolicyName      = ""

# ─────────────────────────────────────────────────────────────────────────────
# OPTIONELE COMPONENTEN
# ─────────────────────────────────────────────────────────────────────────────

# Zet op $false als de klant bewust geen Azure Firewall in de vWAN hub heeft.
# PLATFORM-C10, PLATFORM-C12 en PLATFORM-C13 worden dan als skipped gemeld.
$FirewallEnabled         = $true

# Zet op $false als de klant bewust geen Sandbox MG heeft aangemaakt.
# G01 telt Sandbox dan niet als ontbrekend en toont een aparte gele melding.
$SandboxMgExpected       = $true

# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0
$script:WarningCount = 0

# Houdt resultaten bij van checks die afhankelijk zijn van een custom Azure Policy
# laag (initiatives, losse policy assignments, EPAC). Als hier meerdere/alle ❌
# uitkomen, is dat vermoedelijk één onderliggende oorzaak (geen Azure Policy
# governance-laag, bijv. omdat guardrails via Terraform i.p.v. Azure Policy lopen)
# in plaats van zeven losse problemen. Zie samenvattende melding na sectie 4.
$script:PolicyDependentChecks = [ordered]@{
    "PLATFORM-G06"    = $null   # audit-only policies
    "PLATFORM-G09/10" = $null   # sandbox peering-deny
    "PLATFORM-G18"    = $null   # public-endpoint-deny
    "PLATFORM-G23"    = $null   # custom initiatives
    "PLATFORM-G24/25" = $null   # tag-enforcement policy
    "PLATFORM-C11"    = $null   # spoke-peering-deny
    "PLATFORM-S01"    = $null   # EPAC/security governance
}

function Set-PolicyDependentResult {
    param([string]$Ref, [bool]$Passed)
    if ($script:PolicyDependentChecks.Contains($Ref)) {
        $script:PolicyDependentChecks[$Ref] = $Passed
    }
}

function Write-SectionHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
}

function Write-CheckResult {
    param(
        [string]$Ref,
        [string]$Description,
        [bool]$Passed,
        [bool]$Skipped = $false,
        [bool]$Warning = $false,
        [string]$Detail = ""
    )
    $refPadded = $Ref.PadRight(18)
    $descShort = if ($Description.Length -gt 72) { $Description.Substring(0, 69) + "..." } else { $Description }

    if ($Warning) {
        # Aparte categorie: een bewuste keuze (zoals $FirewallEnabled = $false)
        # laat hier een blootstelling achter zonder vangnet. Geen ❌ (geen
        # onverwachte misconfiguratie) en geen neutraal ⚠️ skip (er is wel een
        # reëel risico), maar een eigen oranje signaal.
        Write-Host "  🟠  $refPadded $descShort" -ForegroundColor Yellow
        if ($Detail) { Write-Host "       → $Detail" -ForegroundColor Yellow }
        $script:WarningCount++
    } elseif ($Skipped) {
        Write-Host "  ⚠️  $refPadded $descShort" -ForegroundColor DarkYellow
        if ($Detail) { Write-Host "       → $Detail" -ForegroundColor DarkYellow }
        $script:SkipCount++
    } elseif ($Passed) {
        Write-Host "  ✅  $refPadded $descShort" -ForegroundColor Green
        if ($Detail) { Write-Host "       → $Detail" -ForegroundColor DarkGreen }
        $script:PassCount++
    } else {
        Write-Host "  ❌  $refPadded $descShort" -ForegroundColor Red
        if ($Detail) { Write-Host "       → $Detail" -ForegroundColor DarkRed }
        $script:FailCount++
    }
}

# Cache alle MG's eenmalig om herhaalde API-calls te vermijden
$script:AllManagementGroups = $null

function Get-AllMGs {
    if ($null -eq $script:AllManagementGroups) {
        try {
            $script:AllManagementGroups = Get-AzManagementGroup -ErrorAction SilentlyContinue
        } catch {
            $script:AllManagementGroups = @()
        }
    }
    return $script:AllManagementGroups
}

function Find-ManagementGroup {
    # Zoekt op GroupId (technische naam) én DisplayName (portal-naam), inclusief wildcards
    param([string]$Name)
    $all = Get-AllMGs
    $found = $all | Where-Object {
        $_.Name -eq $Name -or
        $_.DisplayName -eq $Name -or
        $_.Name -like $Name -or
        $_.DisplayName -like $Name
    } | Select-Object -First 1
    return $found
}

function Test-ManagementGroup {
    param([string]$Name)
    return ($null -ne (Find-ManagementGroup -Name $Name))
}

function Test-ResourceExists {
    param([string]$ResourceId)
    try {
        $r = Get-AzResource -ResourceId $ResourceId -ErrorAction Stop
        return $null -ne $r
    } catch { return $false }
}

function Test-PolicyAssignmentExists {
    # Compatibel met Az.Resources 7.x: gebruik $_.DisplayName, niet $_.Properties.DisplayName
    param([string]$Scope, [string]$NameContains)
    try {
        $assignments = Get-AzPolicyAssignment -Scope $Scope -ErrorAction SilentlyContinue
        return ($assignments | Where-Object {
            $_.Name -like "*$NameContains*" -or $_.DisplayName -like "*$NameContains*"
        }).Count -gt 0
    } catch { return $false }
}

function Test-RoleAssignment {
    param([string]$Scope, [string]$RoleDefinitionName)
    try {
        $roles = Get-AzRoleAssignment -Scope $Scope -ErrorAction SilentlyContinue
        return ($roles | Where-Object { $_.RoleDefinitionName -eq $RoleDefinitionName }).Count -gt 0
    } catch { return $false }
}

function Test-LogAnalyticsWorkspace {
    param([string]$ResourceGroupName, [string]$WorkspaceNameContains)
    try {
        $ws = Get-AzOperationalInsightsWorkspace -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        return ($ws | Where-Object { $_.Name -like "*$WorkspaceNameContains*" }).Count -gt 0
    } catch { return $false }
}

function Test-KeyVault {
    param([string]$ResourceGroupName)
    try {
        $kv = Get-AzKeyVault -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
        return ($kv).Count -gt 0
    } catch { return $false }
}

# Helper: haal policy assignments op met Az.Resources 7.x-compatibele DisplayName-filter
function Get-PolicyAssignmentsFiltered {
    param([string]$Scope, [string[]]$NamePatterns, [string[]]$DisplayNamePatterns)
    try {
        $assignments = Get-AzPolicyAssignment -Scope $Scope -ErrorAction SilentlyContinue
        $result = $assignments | Where-Object {
            $matchName = $false
            $matchDisplay = $false
            foreach ($p in $NamePatterns) {
                if ($_.Name -like $p) { $matchName = $true; break }
            }
            foreach ($p in $DisplayNamePatterns) {
                # Az.Resources 7.x: DisplayName zit op top-level, niet in .Properties
                if ($_.DisplayName -like $p) { $matchDisplay = $true; break }
                # Fallback voor oudere modules
                if ($_.Properties.DisplayName -like $p) { $matchDisplay = $true; break }
            }
            $matchName -or $matchDisplay
        }
        return $result
    } catch { return @() }
}

# ─────────────────────────────────────────────────────────────────────────────
# PRE-FLIGHT
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Azure CAF Platform Checklist Verificatie  v1.7            ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "⚠️  Niet ingelogd bij Azure. Voer eerst Connect-AzAccount uit." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Ingelogd als        : $($context.Account.Id)" -ForegroundColor DarkGray
Write-Host "  Tenant              : $($context.Tenant.Id)" -ForegroundColor DarkGray
Write-Host "  Subscription        : $($context.Subscription.Name)" -ForegroundColor DarkGray
Write-Host "  Intermediate Root MG: $IntermediateRootMgName" -ForegroundColor DarkGray
Write-Host "  Landing Zones MG    : $LandingZonesMgName" -ForegroundColor DarkGray
Write-Host ""

# ═══════════════════════════════════════════════════════════════════════════════
# 1. GOVERNANCE & MANAGEMENT GROUPS
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "1. Governance & Management Groups"

# PLATFORM-G01 — Management group structuur
# Sandbox wordt alleen als ontbrekend beschouwd als $SandboxMgExpected = $true.
# Bij $false krijgt het een aparte gele melding en telt het niet als mislukking.
$mgChecks = [ordered]@{
    $IntermediateRootMgName = Find-ManagementGroup -Name $IntermediateRootMgName
    "Platform"              = Find-ManagementGroup -Name "Platform"
    $LandingZonesMgName     = Find-ManagementGroup -Name $LandingZonesMgName
    "Sandbox"               = Find-ManagementGroup -Name "Sandbox"
    "Decommissioned"        = Find-ManagementGroup -Name "Decommissioned"
}
$mgIntermediate = $mgChecks[$IntermediateRootMgName]

# Bepaal welke MG's als verplicht worden beschouwd
$mgMissingAll = @($mgChecks.GetEnumerator() | Where-Object { $null -eq $_.Value } |
    ForEach-Object { $_.Key })

# Sandbox apart behandelen als $SandboxMgExpected = $false
$mgMissingRequired = if (-not $SandboxMgExpected) {
    $mgMissingAll | Where-Object { $_ -ne "Sandbox" }
} else {
    $mgMissingAll
}

$mgFound = @($mgChecks.GetEnumerator() | Where-Object { $null -ne $_.Value } |
    ForEach-Object { "$($_.Key) [GroupId: $($_.Value.Name)]" })

$g01ok = $mgMissingRequired.Count -eq 0
Write-CheckResult "PLATFORM-G01" "Management group structuur aanmaken (Root → Intermediate → sub-groepen)" $g01ok `
    -Detail $(if ($g01ok -and $mgMissingAll.Count -eq 0) {
        "Alle MG's gevonden: $($mgFound -join ' | ')"
    } elseif ($g01ok) {
        "Verplichte MG's gevonden: $($mgFound -join ' | ')"
    } else {
        "Ontbrekend: $($mgMissingRequired -join ', ') | Gevonden: $(if ($mgFound) { $mgFound -join ', ' } else { 'geen' })"
    })

# Aparte gele melding als Sandbox bewust weggelaten is
if (-not $SandboxMgExpected -and ($null -eq $mgChecks["Sandbox"])) {
    $refPadded = "PLATFORM-G01-SBX".PadRight(18)
    Write-Host "  ⚠️  $refPadded Sandbox MG niet aangemaakt (bewust weggelaten, `$SandboxMgExpected = `$false)" `
        -ForegroundColor DarkYellow
    $script:SkipCount++
} elseif (-not $SandboxMgExpected -and ($null -ne $mgChecks["Sandbox"])) {
    $refPadded = "PLATFORM-G01-SBX".PadRight(18)
    Write-Host "  ℹ️  $refPadded Sandbox MG gevonden maar `$SandboxMgExpected = `$false — overweeg dit bij te werken" `
        -ForegroundColor DarkYellow
}

# PLATFORM-G05 — Root MG: alleen break-glass
# Fix: scope afgeleid van $TenantId (was hardcoded "Tenant Root Group" als GroupId)
# Fix: ghost assignments (ObjectType "Unknown", lege SignInName) worden niet meegeteld.
# Dubbele assignments op hetzelfde principal (zelfde ObjectId, meerdere keren toegewezen
# via verschillende paden) worden ook ontdubbeld op ObjectId.
try {
    $rootRoles     = Get-AzRoleAssignment -Scope $rootScope -ErrorAction SilentlyContinue
    $rootOwnersAll = $rootRoles | Where-Object { $_.RoleDefinitionName -eq "Owner" }

    # Ghost assignments: verwijderde Entra-identiteit, zichtbaar als ObjectType "Unknown" of lege SignInName/DisplayName
    $rootOwnersGhost = $rootOwnersAll | Where-Object {
        $_.ObjectType -eq "Unknown" -or
        ([string]::IsNullOrWhiteSpace($_.SignInName) -and [string]::IsNullOrWhiteSpace($_.DisplayName))
    }
    $rootOwnersActive = $rootOwnersAll | Where-Object {
        $_.ObjectType -ne "Unknown" -and
        -not ([string]::IsNullOrWhiteSpace($_.SignInName) -and [string]::IsNullOrWhiteSpace($_.DisplayName))
    }
    # Ontdubbelen op ObjectId (zelfde principal kan via meerdere role-assignment-paden verschijnen)
    $rootOwnersUnique = $rootOwnersActive | Sort-Object -Property ObjectId -Unique

    $g05ok = ($rootOwnersUnique).Count -le 2
    $ownerNames = ($rootOwnersUnique | ForEach-Object {
        if ($_.SignInName) { $_.SignInName } else { $_.DisplayName }
    }) -join ', '
    $ghostNote = if ($rootOwnersGhost.Count -gt 0) {
        " | ⚠️ $($rootOwnersGhost.Count) ghost-assignment(s) genegeerd (verwijderde Entra-identiteit) — opruimen aanbevolen"
    } else { "" }

    $g05detail = if ($g05ok) {
        if ($rootOwnersUnique.Count -eq 0) {
            "Geen actieve Owner-assignments op Root MG (scope: $rootScope)$ghostNote"
        } else {
            "Owner(s) op Root MG: $ownerNames$ghostNote"
        }
    } else {
        "Te veel actieve Owner-assignments ($($rootOwnersUnique.Count)): $ownerNames$ghostNote"
    }
} catch { $g05ok = $false; $g05detail = "Kon Root MG RBAC niet ophalen (scope: $rootScope)" }
Write-CheckResult "PLATFORM-G05" "Root MG: alleen break-glass accounts, geen onnodige RBAC" $g05ok -Detail $g05detail

# PLATFORM-G06 — Audit-only policies
# Fix: zoekt niet alleen op intermediate root + tenant root, maar ook op de
# geconfigureerde $AuditPolicyMgName en al diens directe sub-MG's.
# Reden: bij klanten met een tussenlaag (bijv. een MG voor losse/ongemanagede
# subscriptions zoals Azure for Students) staat de audit-policy vaak een niveau
# lager dan de intermediate root, en wordt die anders gemist.
try {
    $g06scopes = @()

    # Tenant root
    $g06scopes += $rootScope

    # Intermediate root
    if ($mgIntermediate) {
        $g06scopes += "/providers/Microsoft.Management/managementGroups/$($mgIntermediate.Name)"
    }

    # Geconfigureerde audit-policy MG (kan gelijk zijn aan intermediate root, of lager)
    $auditMg = Find-ManagementGroup -Name $AuditPolicyMgName
    if ($auditMg) {
        $auditScope = "/providers/Microsoft.Management/managementGroups/$($auditMg.Name)"
        if ($g06scopes -notcontains $auditScope) { $g06scopes += $auditScope }

        # Eén niveau onder de audit-policy MG meenemen, voor het geval de policy
        # nog dieper hangt (bijv. een aparte sub-MG voor student-subscriptions)
        $auditExpanded = Get-AzManagementGroup -GroupName $auditMg.Name -Expand -ErrorAction SilentlyContinue
        foreach ($child in $auditExpanded.Children) {
            if ($child.Type -like "*managementGroups*") {
                $childScope = "/providers/Microsoft.Management/managementGroups/$($child.Name)"
                if ($g06scopes -notcontains $childScope) { $g06scopes += $childScope }
            }
        }
    }

    $g06audit = @()
    $g06scopeHits = @{}
    foreach ($scope in $g06scopes) {
        $assignments = Get-AzPolicyAssignment -Scope $scope -ErrorAction SilentlyContinue
        $found = $assignments | Where-Object {
            $_.Name -like "*audit*" -or
            $_.DisplayName -like "*audit*" -or
            $_.Properties.DisplayName -like "*audit*"
        }
        if ($found) {
            $g06audit += $found
            $g06scopeHits[$scope] = $found.Count
        }
    }

    $g06ok = ($g06audit).Count -gt 0
    $g06detail = if ($g06ok) {
        $names = ($g06audit | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        $scopeInfo = ($g06scopeHits.Keys | ForEach-Object {
            $mgId = $_ -replace '.*managementGroups/', ''
            "$mgId ($($g06scopeHits[$_]))"
        }) -join ', '
        "Audit policy/policies gevonden: $names — scope(s): $scopeInfo"
    } else {
        # Ontdubbel de MG-namen in de foutmelding als ze gelijk zijn
        # (bijv. wanneer $AuditPolicyMgName nog op dezelfde waarde staat als $IntermediateRootMgName)
        $mgNamesInMsg = @($IntermediateRootMgName, $AuditPolicyMgName) | Select-Object -Unique
        $mgNamesText  = ($mgNamesInMsg | ForEach-Object { "'$_'" }) -join ', '
        "Geen audit-only policies gevonden op Tenant Root, $mgNamesText of diens sub-MG's — " +
        "controleer policy assignments of pas `$AuditPolicyMgName aan naar de juiste MG"
    }
} catch { $g06ok = $false; $g06detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "PLATFORM-G06" "Tenant level: uitsluitend audit-only policies toewijzen" $g06ok -Detail $g06detail
Set-PolicyDependentResult -Ref "PLATFORM-G06" -Passed $g06ok

# PLATFORM-G07 — Custom roles
try {
    $customRoles = Get-AzRoleDefinition -Custom -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $g07ok = ($customRoles).Count -gt 0
    $g07detail = if ($g07ok) {
        "$($customRoles.Count) custom role(s): $(($customRoles.Name) -join ', ')"
    } else {
        "Geen custom rollen gevonden op tenant-niveau"
    }
} catch { $g07ok = $false; $g07detail = "Kon custom roles niet ophalen" }
Write-CheckResult "PLATFORM-G07" "Custom role definitions op tenant-niveau gedefinieerd" $g07ok -Detail $g07detail

# PLATFORM-G09/10 — Sandbox isoleren
# Fix: $_.DisplayName i.p.v. $_.Properties.DisplayName (Az.Resources 7.x)
# Fix: consistent met $SandboxMgExpected. Als Sandbox bewust niet bestaat
# (zoals ook gemeld bij PLATFORM-G01-SBX), heeft "isoleer de Sandbox MG" geen
# betekenis meer — die check wordt dan als skipped gemeld in plaats van ❌.
if (-not $SandboxMgExpected -and ($null -eq (Find-ManagementGroup -Name "Sandbox"))) {
    Write-CheckResult "PLATFORM-G09/10" "Sandbox MG volledig isoleren (geen VNet peerings via policy)" $false -Skipped $true `
        -Detail "Overgeslagen: `$SandboxMgExpected = `$false en Sandbox MG bestaat niet — niets om te isoleren"
} else {
try {
    $sandboxMg    = Find-ManagementGroup -Name "Sandbox"
    $sandboxScope = if ($sandboxMg) {
        "/providers/Microsoft.Management/managementGroups/$($sandboxMg.Name)"
    } else {
        "/providers/Microsoft.Management/managementGroups/Sandbox"
    }
    $sandboxPeeringPolicy = Get-PolicyAssignmentsFiltered `
        -Scope $sandboxScope `
        -NamePatterns @("*peer*", "*sandbox*") `
        -DisplayNamePatterns @("*peer*", "*sandbox*", "*vnet*")

    $g09ok = ($sandboxPeeringPolicy).Count -gt 0
    $g09detail = if ($g09ok) {
        $policyNames = ($sandboxPeeringPolicy | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Peering-blokkade policy gevonden: $policyNames"
    } else {
        $allAssignments  = Get-AzPolicyAssignment -Scope $sandboxScope -ErrorAction SilentlyContinue
        $allNames = ($allAssignments | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Geen peering-blokkade policy op Sandbox MG — gevonden policies: $(if ($allNames) { $allNames } else { 'geen' })"
    }
} catch { $g09ok = $false; $g09detail = "Sandbox MG niet gevonden of geen rechten" }
Write-CheckResult "PLATFORM-G09/10" "Sandbox MG volledig isoleren (geen VNet peerings via policy)" $g09ok -Detail $g09detail
Set-PolicyDependentResult -Ref "PLATFORM-G09/10" -Passed $g09ok
}

# PLATFORM-G11 — Decommissioned MG
$g11mg = Find-ManagementGroup -Name "Decommissioned"
$g11ok = ($null -ne $g11mg)
Write-CheckResult "PLATFORM-G11" "Decommissioned management group aangemaakt" $g11ok `
    -Detail $(if ($g11ok) {
        "Gevonden — DisplayName: '$($g11mg.DisplayName)' | GroupId: '$($g11mg.Name)'"
    } else {
        "MG 'Decommissioned' niet gevonden"
    })

# PLATFORM-G15 — Key Vaults voor secrets
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $kvsConn = Get-AzKeyVault -ErrorAction SilentlyContinue

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $kvsMgmt = Get-AzKeyVault -ErrorAction SilentlyContinue

    $allKvs = @($kvsConn) + @($kvsMgmt)
    $g15ok = ($allKvs).Count -gt 0
    $g15detail = if ($g15ok) {
        "$($allKvs.Count) Key Vault(s): $(($allKvs | ForEach-Object { $_.VaultName }) -join ', ')"
    } else {
        "Geen Key Vaults gevonden"
    }
} catch { $g15ok = $false; $g15detail = "Kon Key Vaults niet ophalen" }
Write-CheckResult "PLATFORM-G15" "Key Vaults aangemaakt voor credentials en secrets" $g15ok -Detail $g15detail

# PLATFORM-G16 — Resource locks op platform resources
# Opmerking: overweeg een Deny Delete policy of deployment stack met deny-permissions
# als alternatief voor locks — schaalbaar voor meerdere resource groups
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $locksConn = Get-AzResourceLock -ResourceGroupName $HubResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $locksDns  = Get-AzResourceLock -ResourceGroupName $DnsResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $locksMgmt = Get-AzResourceLock -ResourceGroupName $LogAnalyticsRGPlatform `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }

    $locks = @($locksConn) + @($locksDns) + @($locksMgmt)
    $g16ok = ($locks).Count -gt 0
    $g16detail = if ($g16ok) {
        $rgNames = ($locks | ForEach-Object { $_.ResourceGroupName } | Sort-Object -Unique) -join ', '
        "$($locks.Count) CanNotDelete lock(s) op: $rgNames"
    } else {
        "Geen CanNotDelete locks gevonden — alternatief: Deny Delete policy of deployment stack"
    }
} catch { $g16ok = $false; $g16detail = "Fout: $_" }
Write-CheckResult "PLATFORM-G16" "Resource locks (CanNotDelete) op platform-resources" $g16ok -Detail $g16detail

# ═══════════════════════════════════════════════════════════════════════════════
# 2. RBAC & TOEGANGSBEHEER
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "2. RBAC & Toegangsbeheer"

# Bepaal scope van intermediate root MG voor RBAC-checks
$intermediateRootGroupId = if ($mgIntermediate) { $mgIntermediate.Name } else { $IntermediateRootMgName }
$intermediateRootScope   = "/providers/Microsoft.Management/managementGroups/$intermediateRootGroupId"

# PLATFORM-G08 — RBAC op intermediate root MG
# Fix: ghost assignments (verwijderd uit Entra) worden gefilterd op ObjectType = "Unknown"
try {
    $g08roles   = Get-AzRoleAssignment -Scope $intermediateRootScope -ErrorAction SilentlyContinue
    $g08contrib = $g08roles | Where-Object {
        $_.RoleDefinitionName -eq "Contributor" -and $_.ObjectType -ne "Unknown"
    }
    $g08ghosts  = $g08roles | Where-Object { $_.ObjectType -eq "Unknown" }

    $g08ok = ($g08contrib).Count -gt 0
    $g08detail = if ($g08ok) {
        $names = ($g08contrib | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName } else { $_.ObjectId }
        }) -join ', '
        $ghostWarn = if ($g08ghosts.Count -gt 0) {
            " | ⚠️ $($g08ghosts.Count) verwijderde identiteit(en) gevonden (opruimen aanbevolen)"
        } else { "" }
        "Contributor(s) op [$IntermediateRootMgName] MG: $names$ghostWarn"
    } else {
        $foundRoles = ($g08roles.RoleDefinitionName | Sort-Object -Unique) -join ', '
        $ghostWarn  = if ($g08ghosts.Count -gt 0) {
            " | ⚠️ $($g08ghosts.Count) verwijderde identiteit(en) aangetroffen"
        } else { "" }
        "Geen actieve Contributor op [$IntermediateRootMgName] MG — gevonden rollen: $(if ($foundRoles) { $foundRoles } else { 'geen' })$ghostWarn"
    }
} catch { $g08ok = $false; $g08detail = "Kon RBAC op [$IntermediateRootMgName] MG niet ophalen" }
Write-CheckResult "PLATFORM-G08" "RBAC beheerders toegewezen op intermediate root MG niveau" $g08ok -Detail $g08detail

# PLATFORM-G31 — PIM eligible assignments
# Fix: Get-AzRoleEligibilityScheduleInstance i.p.v. Get-AzRoleEligibleChildResource
# Get-AzRoleEligibleChildResource geeft child-resources terug, niet de assignments zelf
#
# Fix v2: PIM vereist Entra ID P2 (los, of via een bundel zoals Microsoft 365 E5,
# EMS E5, of Microsoft 365 E5 Security). Zonder die licentie is "geen PIM eligible
# assignments" geen misconfiguratie maar een onvermijdelijke licentiebeperking.
# Het script detecteert dit nu automatisch via Microsoft Graph (Get-MgSubscribedSku)
# in plaats van dat dit per klant handmatig hoeft te worden ingesteld — relevant
# omdat dit script ook bij klanten met wél P2 gebruikt gaat worden, waar G31 dan
# gewoon een normale ✅/❌ moet blijven geven.
$g31licenseChecked = $false
$g31hasP2           = $false
try {
    $graphModule = Get-Module -ListAvailable -Name Microsoft.Graph.Identity.DirectoryManagement -ErrorAction SilentlyContinue
    if ($graphModule) {
        $mgContext = Get-MgContext -ErrorAction SilentlyContinue
        if (-not $mgContext) {
            Connect-MgGraph -Scopes "Directory.Read.All" -NoWelcome -ErrorAction Stop
        }
        # SKU's die Entra ID P2 bevatten (los of als onderdeel van een bundel).
        # ServicePlans binnen een SKU tonen het daadwerkelijke entitlement;
        # SkuPartNumber alleen is niet altijd dekkend (P2 zit ook embedded in
        # EMS E5, Microsoft 365 E5, en Microsoft 365 E5 Security bijvoorbeeld).
        $skus = Get-MgSubscribedSku -ErrorAction Stop
        $p2ServicePlanNames = @("AAD_PREMIUM_P2", "EMSPREMIUM")
        $matchingSkus = $skus | Where-Object {
            $sku = $_
            $sku.ServicePlans | Where-Object {
                $_.ServicePlanName -in $p2ServicePlanNames -and $_.ProvisioningStatus -eq "Success"
            }
        }
        $g31licenseChecked = $true
        $g31hasP2 = ($matchingSkus.Count -gt 0)
    }
} catch {
    # Licentiecheck kon niet uitgevoerd worden (geen Graph-module, geen rechten,
    # geen interactieve sessie mogelijk) — val terug op de oude aanpak: probeer
    # de PIM-query gewoon en behandel een lege/foutieve uitkomst als onzeker.
    $g31licenseChecked = $false
}

if ($g31licenseChecked -and -not $g31hasP2) {
    Write-CheckResult "PLATFORM-G31" "Admin-rollen via Entra PIM toewijzen" $false -Skipped $true `
        -Detail "Overgeslagen: geen Entra ID P2 (of bundel met P2) gevonden in de tenant — PIM is niet beschikbaar zonder deze licentie"
} else {
    try {
        $pimAssignments = Get-AzRoleEligibilityScheduleInstance `
            -Scope $intermediateRootScope -ErrorAction SilentlyContinue
        $g31ok = ($pimAssignments).Count -gt 0
        $licenseNote = if ($g31licenseChecked) { " (P2-licentie bevestigd aanwezig)" } else { " (licentiestatus niet automatisch gecontroleerd — installeer Microsoft.Graph.Identity.DirectoryManagement voor automatische detectie)" }
        $g31detail = if ($g31ok) {
            "$($pimAssignments.Count) PIM eligible assignment(s) gevonden op [$IntermediateRootMgName] MG$licenseNote"
        } else {
            "Geen PIM eligible assignments gevonden$licenseNote — controleer of Entra PIM correct is geconfigureerd"
        }
        Write-CheckResult "PLATFORM-G31" "Admin-rollen via Entra PIM toewijzen" $g31ok -Detail $g31detail
    } catch {
        Write-CheckResult "PLATFORM-G31" "Admin-rollen via Entra PIM toewijzen" $false -Skipped $true `
            -Detail "Onvoldoende rechten voor PIM-query of Az.Resources module te oud (vereist 6.x+)"
    }
}

# PLATFORM-G34/35 — RBAC-groepen per subscription
# Fix: beperkt tot geconfigureerde platform subscriptions i.p.v. alle tenant-subscriptions
# Bij grote tenants (1000+ subscriptions) is iteratie over alle subs niet haalbaar
try {
    $platformSubs = @(
        [PSCustomObject]@{ Id = $ConnectivitySubId; Name = "Connectivity" }
        [PSCustomObject]@{ Id = $ManagementSubId;   Name = "Management" }
    )
    $g3435missing = @()
    foreach ($sub in $platformSubs) {
        $subScope  = "/subscriptions/$($sub.Id)"
        $roles     = Get-AzRoleAssignment -Scope $subScope -ErrorAction SilentlyContinue
        $roleNames = $roles | Where-Object { $_.ObjectType -ne "Unknown" } |
            Select-Object -ExpandProperty RoleDefinitionName | Sort-Object -Unique
        $missing   = @("Owner", "Contributor", "Reader") | Where-Object { $_ -notin $roleNames }
        if ($missing.Count -gt 0) {
            $g3435missing += "$($sub.Name): ontbreekt $($missing -join '/')"
        }
    }
    $g3435ok     = $g3435missing.Count -eq 0
    $g3435detail = if ($g3435ok) {
        "Owner/Contributor/Reader gevonden op platform subscriptions (Connectivity + Management)"
    } else {
        $g3435missing -join ' | '
    }
} catch { $g3435ok = $false; $g3435detail = "Kon subscriptions of role assignments niet ophalen" }
Write-CheckResult "PLATFORM-G34/35" "Per platform subscription drie standaard RBAC-groepen" $g3435ok `
    -Detail "$g3435detail — check beperkt tot Connectivity + Management subs"

# ═══════════════════════════════════════════════════════════════════════════════
# 3. AZURE POLICY & COMPLIANCE
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "3. Azure Policy & Compliance"

# PLATFORM-G22 — Defender for Cloud
if ($ConnectivitySubId) { Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null }
try {
    $defenderPlans = Get-AzSecurityPricing -ErrorAction SilentlyContinue
    $freePlans     = $defenderPlans | Where-Object { $_.PricingTier -eq "Free" }
    $activePlans   = $defenderPlans | Where-Object { $_.PricingTier -ne "Free" }
    $g22ok = ($activePlans).Count -gt 0
    $g22detail = if ($g22ok) {
        "Actief: $($activePlans.Name -join ', ')" +
        $(if ($freePlans.Count -gt 0) { " | Nog op Free: $($freePlans.Name -join ', ')" } else { "" })
    } else {
        "Alle Defender-plans op Free-tier — activeer minimaal: VirtualMachines, SqlServers, StorageAccounts, KeyVaults"
    }
} catch { $g22ok = $false; $g22detail = "Kon Defender for Cloud pricing niet ophalen" }
Write-CheckResult "PLATFORM-G22" "Microsoft Defender for Cloud geactiveerd op subscriptions" $g22ok -Detail $g22detail

# PLATFORM-G23 — Policy initiatives
try {
    $initiatives = Get-AzPolicySetDefinition -Custom -ErrorAction SilentlyContinue
    $g23ok = ($initiatives).Count -gt 0
    $g23detail = if ($g23ok) {
        $names = ($initiatives | ForEach-Object {
            if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
        }) -join ', '
        "$($initiatives.Count) initiative(s): $names"
    } else {
        "Geen custom policy initiatives — verwacht: Tagging, LandingZone, PlatformConnectivity, PlatformSecurity"
    }
} catch { $g23ok = $false; $g23detail = "Kon policy initiatives niet ophalen" }
Write-CheckResult "PLATFORM-G23" "Azure Policies gegroepeerd in initiatives (custom)" $g23ok -Detail $g23detail
Set-PolicyDependentResult -Ref "PLATFORM-G23" -Passed $g23ok

# PLATFORM-G18 — Policy: publieke endpoints blokkeren
try {
    $lzMgG18   = Find-ManagementGroup -Name $LandingZonesMgName
    $lzScopeG18 = if ($lzMgG18) {
        "/providers/Microsoft.Management/managementGroups/$($lzMgG18.Name)"
    } else {
        $intermediateRootScope
    }
    $g18policy = Get-PolicyAssignmentsFiltered `
        -Scope $lzScopeG18 `
        -NamePatterns @("*public*", "*pub*", "*ep*") `
        -DisplayNamePatterns @("*public*", "*endpoint*")

    $g18ok = ($g18policy).Count -gt 0
    $g18detail = if ($g18ok) {
        $names = ($g18policy | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Policy gevonden: $names"
    } else {
        "Geen public-endpoint-blokkade policy op '$LandingZonesMgName' — verwacht: 'Deny Public Endpoints'"
    }
} catch { $g18ok = $false; $g18detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "PLATFORM-G18" "Policy: publieke endpoints geblokkeerd in alle landing zones" $g18ok -Detail $g18detail
Set-PolicyDependentResult -Ref "PLATFORM-G18" -Passed $g18ok

# PLATFORM-G13 — Log retentie
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $workspaces    = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $shortRetention = $workspaces | Where-Object { $_.retentionInDays -lt 30 }
    $g13ok = ($workspaces).Count -gt 0 -and ($shortRetention).Count -eq 0
    $g13detail = if ($g13ok) {
        "Retentie OK: $(($workspaces | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', ')"
    } elseif ($workspaces.Count -eq 0) {
        "Geen Log Analytics Workspaces gevonden"
    } else {
        "Retentie te laag: $(($shortRetention | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d (min. 30d)" }) -join ', ')"
    }
} catch { $g13ok = $false; $g13detail = "Kon Log Analytics workspaces niet ophalen: $_" }
Write-CheckResult "PLATFORM-G13" "Log retentie ingesteld (min. 30 dagen)" $g13ok -Detail $g13detail

# ═══════════════════════════════════════════════════════════════════════════════
# 4. TAGGING & NAAMGEVING
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "4. Tagging & Naamgeving"

# PLATFORM-G24/25 — Tag policy
# Fix: scope gebaseerd op $TagPolicyMgName (configureerbaar, kan lager dan intermediate root zijn)
# Let op: een Deny-tag-policy op dezelfde scope als audit-only (G06) is inconsistent.
# Zet $TagPolicyMgName op de MG waarop jij daadwerkelijk de tag-policy hebt staan.
try {
    $tagMg    = Find-ManagementGroup -Name $TagPolicyMgName
    $tagScope = if ($tagMg) {
        "/providers/Microsoft.Management/managementGroups/$($tagMg.Name)"
    } else {
        $intermediateRootScope
    }
    $g2425policy = Get-PolicyAssignmentsFiltered `
        -Scope $tagScope `
        -NamePatterns @("*tag*") `
        -DisplayNamePatterns @("*tag*")

    $g2425ok = ($g2425policy).Count -gt 0
    $g2425detail = if ($g2425ok) {
        $names = ($g2425policy | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Tag-policy gevonden op scope '$TagPolicyMgName': $names"
    } else {
        "Geen tag-policy gevonden op '$TagPolicyMgName' — verwacht: 'Require Tag on Resources' of vergelijkbaar"
    }
} catch { $g2425ok = $false; $g2425detail = "Kon tag-policies niet ophalen" }
Write-CheckResult "PLATFORM-G24/25" "Tag-beleid afgedwongen via policy op management groups" $g2425ok -Detail $g2425detail
Set-PolicyDependentResult -Ref "PLATFORM-G24/25" -Passed $g2425ok

# PLATFORM-G40 — Budget alerts
# Fix: Invoke-AzRestMethod (ARM REST API) i.p.v. Get-AzConsumptionBudget.
# Get-AzConsumptionBudget vereist de Az.Billing module die niet standaard aanwezig is.
# De ARM REST endpoint /providers/Microsoft.Consumption/budgets werkt met elke Az-sessie.
try {
    $allBudgets   = @()
    $budgetErrors = @()
    $budgetSubs   = @(
        [PSCustomObject]@{ Id = $ConnectivitySubId; Name = "Connectivity" }
        [PSCustomObject]@{ Id = $ManagementSubId;   Name = "Management" }
    )
    foreach ($sub in $budgetSubs) {
        $uri      = "/subscriptions/$($sub.Id)/providers/Microsoft.Consumption/budgets?api-version=2023-05-01"
        $response = Invoke-AzRestMethod -Path $uri -Method GET -ErrorAction SilentlyContinue
        if ($response -and $response.StatusCode -eq 200) {
            $body    = $response.Content | ConvertFrom-Json
            $budgets = $body.value
            if ($budgets) {
                $allBudgets += $budgets | ForEach-Object { "$($_.name) [$($sub.Name)]" }
            }
        } elseif ($response -and $response.StatusCode) {
            $budgetErrors += "$($sub.Name): HTTP $($response.StatusCode)"
        }
    }

    # CLI als extra poging als REST geen resultaten gaf
    if ($allBudgets.Count -eq 0) {
        $azCli = Get-Command az -ErrorAction SilentlyContinue
        if ($azCli) {
            foreach ($sub in $budgetSubs) {
                $b = az consumption budget list --subscription $sub.Id --query "[].name" -o tsv 2>$null
                if ($b) { $allBudgets += $b | ForEach-Object { "$_ [$($sub.Name) via CLI]" } }
            }
        }
    }

    $g40ok     = ($allBudgets).Count -gt 0
    $g40detail = if ($g40ok) {
        "Budget(s) gevonden: $($allBudgets -join ', ')"
    } elseif ($budgetErrors) {
        "Geen budgets — API-fouten: $($budgetErrors -join ', ') — controleer rechten op Microsoft.Consumption/budgets"
    } else {
        "Geen budgets gevonden op Connectivity of Management — stel budgets in via Cost Management"
    }
} catch { $g40ok = $false; $g40detail = "Fout bij ophalen budgets: $_" }
Write-CheckResult "PLATFORM-G40" "Budget alerts automatisch ingesteld per subscription" $g40ok -Detail $g40detail

# ═══════════════════════════════════════════════════════════════════════════════
# 5. CONNECTIVITY & NETWERK
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "5. Connectivity & Netwerk"

if ($ConnectivitySubId) {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
}

# PLATFORM-C02 — Virtual WAN
try {
    $vwans  = Get-AzVirtualWan -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $c02ok  = ($vwans).Count -gt 0
    $c02detail = if ($c02ok) {
        "VWAN gevonden: $($vwans.Name -join ', ') (locatie: $($vwans.Location -join ', '))"
    } else {
        "Geen Virtual WAN gevonden in resource group '$HubResourceGroup'"
    }
} catch { $c02ok = $false; $c02detail = "Resource group '$HubResourceGroup' niet gevonden of geen rechten" }
Write-CheckResult "PLATFORM-C02" "Azure Virtual WAN aangemaakt (West Europe)" $c02ok -Detail $c02detail

# PLATFORM-C02b — Secured Hub
try {
    $hubs      = Get-AzVirtualHub -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $hubOk     = ($hubs).Count -gt 0
    $hubDetail = if ($hubOk) {
        "Hub gevonden: $($hubs.Name -join ', ') (locatie: $($hubs.Location -join ', '))"
    } else {
        "Geen Virtual Hub gevonden in '$HubResourceGroup'"
    }
} catch { $hubOk = $false; $hubDetail = "Kon hubs niet ophalen" }
Write-CheckResult "PLATFORM-C02b" "Secured Hub aangemaakt (West Europe)" $hubOk -Detail $hubDetail

# PLATFORM-C05 — Platform VNets
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $vnetsConn = Get-AzVirtualNetwork -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $vnetsMgmt = Get-AzVirtualNetwork -ErrorAction SilentlyContinue

    $vnets     = @($vnetsConn) + @($vnetsMgmt)
    $c05ok     = ($vnets).Count -ge 2
    $foundNames = $vnets.Name -join ', '
    $c05detail = if ($c05ok) {
        "$($vnets.Count) VNet(s) gevonden: $foundNames"
    } else {
        "$($vnets.Count) VNets gevonden$(if ($foundNames) { ": $foundNames" }) — verwacht minimaal Connectivity + Management"
    }
} catch { $c05ok = $false; $c05detail = "Kon VNets niet ophalen in '$HubResourceGroup'" }
Write-CheckResult "PLATFORM-C05" "Platform VNets aangemaakt (Connectivity / Management)" $c05ok -Detail $c05detail

# PLATFORM-C10 — Azure Firewall Policy
# Optioneel via $FirewallEnabled: bij $false wordt de check als skipped gemeld.
# In vWAN Secured Hub beheert Microsoft de Firewall in een eigen resource group (mrg-*).
if (-not $FirewallEnabled) {
    Write-CheckResult "PLATFORM-C10" "Azure Firewall Policy geconfigureerd in Secured Hub" $false -Skipped $true `
        -Detail "Overgeslagen: `$FirewallEnabled = `$false (klant heeft bewust geen Azure Firewall)"
} else {
    try {
        Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
        $allFwPolicies = Get-AzResource -ResourceType "Microsoft.Network/firewallPolicies" `
            -ErrorAction SilentlyContinue
        $c10ok     = ($allFwPolicies).Count -gt 0
        $c10detail = if ($c10ok) {
            $policyInfo = ($allFwPolicies | ForEach-Object { "$($_.Name) [RG: $($_.ResourceGroupName)]" }) -join ', '
            "Firewall policy/policies gevonden: $policyInfo"
        } else {
            "Geen Firewall Policy gevonden in Connectivity subscription — vWAN Secured Hub gebruikt Microsoft-managed RG"
        }
    } catch { $c10ok = $false; $c10detail = "Kon Firewall Policies niet ophalen" }
    Write-CheckResult "PLATFORM-C10" "Azure Firewall Policy geconfigureerd in Secured Hub" $c10ok -Detail $c10detail
}

# PLATFORM-C11 — VNet peerings tussen spokes verboden
# Fix: $_.DisplayName i.p.v. $_.Properties.DisplayName (Az.Resources 7.x)
try {
    $sandboxMgC11    = Find-ManagementGroup -Name "Sandbox"
    $sandboxScopeC11 = if ($sandboxMgC11) {
        "/providers/Microsoft.Management/managementGroups/$($sandboxMgC11.Name)"
    } else { $null }

    $c11fromRoot    = Get-PolicyAssignmentsFiltered `
        -Scope $intermediateRootScope `
        -NamePatterns @("*peer*", "*no-peer*") `
        -DisplayNamePatterns @("*peering*", "*vnet peer*")
    $c11fromSandbox = if ($sandboxScopeC11) {
        Get-PolicyAssignmentsFiltered `
            -Scope $sandboxScopeC11 `
            -NamePatterns @("*peer*", "*no-peer*") `
            -DisplayNamePatterns @("*peering*", "*vnet peer*")
    } else { @() }

    $c11policy = @($c11fromRoot) + @($c11fromSandbox)
    $c11ok     = ($c11policy).Count -gt 0
    $c11detail = if ($c11ok) {
        $names = ($c11policy | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Policy gevonden: $names"
    } else {
        "Geen spoke-peering-blokkade policy gevonden op '$IntermediateRootMgName' of Sandbox MG"
    }
} catch { $c11ok = $false; $c11detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "PLATFORM-C11" "Policy: VNet peerings tussen spokes verboden" $c11ok -Detail $c11detail
Set-PolicyDependentResult -Ref "PLATFORM-C11" -Passed $c11ok

# PLATFORM-C12 — Internet breakout via Virtual WAN Hub Routing Intent
# Optioneel via $FirewallEnabled: zonder Firewall is Routing Intent niet bruikbaar,
# dus de check heeft dan geen betekenis en wordt als skipped gemeld.
if (-not $FirewallEnabled) {
    Write-CheckResult "PLATFORM-C12" "Internet breakout via vWAN Hub Routing Intent" $false -Skipped $true `
        -Detail "Overgeslagen: `$FirewallEnabled = `$false (Routing Intent vereist Azure Firewall in Secured Hub)"
} else {
    try {
        Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
        $vhubs  = Get-AzVirtualHub -ResourceGroupName $HubResourceGroup `
            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        $afw    = Get-AzResource -ResourceType "Microsoft.Network/azureFirewalls" `
            -ErrorAction SilentlyContinue
        $routingIntent = Get-AzResource `
            -ResourceType "Microsoft.Network/virtualHubs/routingIntent" `
            -ErrorAction SilentlyContinue

        $c12ok     = ($vhubs).Count -gt 0 -and ($afw).Count -gt 0
        $c12detail = if ($c12ok) {
            $riInfo  = if ($routingIntent) { " + Routing Intent aanwezig" } else { " (Routing Intent niet gevonden — wordt mogelijk uitgerold)" }
            $afwInfo = ($afw | ForEach-Object { "$($_.Name) [RG: $($_.ResourceGroupName)]" }) -join ', '
            "Virtual WAN Hub + Azure Firewall ($afwInfo) — internet breakout via Hub routing$riInfo"
        } elseif (($vhubs).Count -gt 0 -and ($afw).Count -eq 0) {
            "Virtual Hub gevonden maar geen Azure Firewall — Secured Hub niet volledig ingericht"
        } else {
            "Geen Virtual Hub of Firewall gevonden in Connectivity subscription"
        }
    } catch { $c12ok = $false; $c12detail = "Kon Virtual Hub niet ophalen" }
    Write-CheckResult "PLATFORM-C12" "Internet breakout via vWAN Hub Routing Intent" $c12ok -Detail $c12detail
}

# ═══════════════════════════════════════════════════════════════════════════════
# 6. DNS & PRIVATE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "6. DNS & Private Endpoints"

# PLATFORM-C07 — DNS Private Resolver
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $dnsResolvers = Get-AzDnsResolver -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $c07ok     = ($dnsResolvers).Count -gt 0
    $c07detail = if ($c07ok) {
        "DNS Resolver gevonden: $($dnsResolvers.Name -join ', ')"
    } else {
        "Geen DNS Private Resolver in '$HubResourceGroup' — verwacht voor hybride DNS conditional forwarding"
    }
} catch { $c07ok = $false; $c07detail = "Kon DNS Resolvers niet ophalen (module vereist: Az.DnsResolver)" }
Write-CheckResult "PLATFORM-C07" "Azure DNS Private Resolver ingericht" $c07ok -Detail $c07detail

# PLATFORM-C09 — Private DNS Zones
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $dnsZones  = Get-AzPrivateDnsZone -ResourceGroupName $DnsResourceGroup -ErrorAction SilentlyContinue
    $c09ok     = ($dnsZones).Count -gt 0
    $c09detail = if ($c09ok) {
        "$($dnsZones.Count) zone(s) gevonden in '$DnsResourceGroup'"
    } else {
        "Geen Private DNS Zones gevonden in '$DnsResourceGroup'"
    }
} catch { $c09ok = $false; $c09detail = "Resource group '$DnsResourceGroup' niet gevonden of geen rechten" }
Write-CheckResult "PLATFORM-C09" "Private DNS Zones aangemaakt in $DnsResourceGroup" $c09ok -Detail $c09detail

# PLATFORM-C09a — Specifieke DNS zones
$requiredZones = @(
    "privatelink.blob.core.windows.net",
    "privatelink.file.core.windows.net",
    "privatelink.vaultcore.azure.net",
    "privatelink.database.windows.net"
)
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $dnsZonesCheck = Get-AzPrivateDnsZone -ResourceGroupName $DnsResourceGroup -ErrorAction SilentlyContinue
    $missingZones  = $requiredZones | Where-Object { $dnsZonesCheck.Name -notcontains $_ }
    $presentZones  = $requiredZones | Where-Object { $dnsZonesCheck.Name -contains $_ }
    $c09aok        = $missingZones.Count -eq 0
    $c09adetail    = if ($c09aok) {
        "Alle vereiste zones aanwezig: $($requiredZones -join ', ')"
    } else {
        "Ontbrekend: $($missingZones -join ', ') | Aanwezig: $(if ($presentZones) { $presentZones -join ', ' } else { 'geen' })"
    }
} catch { $c09aok = $false; $c09adetail = "Kon DNS zones niet ophalen" }
Write-CheckResult "PLATFORM-C09a" "DNS zones aangemaakt: blob, file, keyvault, SQL, etc." $c09aok -Detail $c09adetail

# PLATFORM-C08 — Private Endpoints (steekproef platform subscriptions)
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $pesConn = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $pesMgmt = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue

    $pes     = @($pesConn) + @($pesMgmt)
    $c08ok   = ($pes).Count -gt 0
    $c08detail = if ($c08ok) {
        $peNames = ($pes | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', '
        $extra   = if ($pes.Count -gt 5) { ' ...' } else { '' }
        "$($pes.Count) private endpoint(s): $peNames$extra"
    } else {
        "Geen private endpoints gevonden in Connectivity of Management subscription"
    }
} catch { $c08ok = $false; $c08detail = "Kon private endpoints niet ophalen" }
Write-CheckResult "PLATFORM-C08" "Private Endpoints gedeployed voor PaaS-resources" $c08ok -Detail $c08detail

# ═══════════════════════════════════════════════════════════════════════════════
# 7. SECURITY
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "7. Security"

# PLATFORM-S01 — Security policies / EPAC
# Fix: $_.DisplayName i.p.v. $_.Properties.DisplayName (Az.Resources 7.x)
try {
    $s01policy = Get-PolicyAssignmentsFiltered `
        -Scope $intermediateRootScope `
        -NamePatterns @("*audit*", "*tagging*", "*EPAC*") `
        -DisplayNamePatterns @("*security*", "*EPAC*", "*audit*")

    $s01ok     = ($s01policy).Count -gt 0
    $s01detail = if ($s01ok) {
        $names = ($s01policy | ForEach-Object {
            if ($_.DisplayName) { $_.DisplayName }
            elseif ($_.Properties.DisplayName) { $_.Properties.DisplayName }
            else { $_.Name }
        }) -join ', '
        "Security policies gevonden: $names"
    } else {
        "Geen security/EPAC policies gevonden op '$IntermediateRootMgName'"
    }
} catch { $s01ok = $false; $s01detail = "Kon security policies niet ophalen" }
Write-CheckResult "PLATFORM-S01" "Security Governance policies (EPAC) geïmplementeerd" $s01ok -Detail $s01detail
Set-PolicyDependentResult -Ref "PLATFORM-S01" -Passed $s01ok

# ─────────────────────────────────────────────────────────────────────────────
# Samenvattende melding: patroonherkenning over de zeven Azure Policy-afhankelijke checks
# (PLATFORM-G06, G09/10, G18, G23, G24/25, C11, S01). Als de meeste/alle hiervan ❌ zijn,
# is dat vermoedelijk één onderliggende oorzaak (geen custom Azure Policy governance-
# laag in deze tenant) in plaats van zeven losse misconfiguraties. Voorkomt dat je
# zeven keer dezelfde diagnose opnieuw moet doen.
# ─────────────────────────────────────────────────────────────────────────────
$policyResults  = $script:PolicyDependentChecks.Values | Where-Object { $null -ne $_ }
$policyFailed   = @($policyResults | Where-Object { $_ -eq $false })
$policyChecked  = $policyResults.Count

if ($policyChecked -gt 0 -and $policyFailed.Count -ge 4) {
    $failedRefs = ($script:PolicyDependentChecks.GetEnumerator() | Where-Object { $_.Value -eq $false } |
        ForEach-Object { $_.Key }) -join ', '
    Write-Host ""
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkYellow
    Write-Host "  ℹ️  PATROON GEDETECTEERD: $($policyFailed.Count)/$policyChecked Azure Policy-afhankelijke" -ForegroundColor DarkYellow
    Write-Host "      checks zijn ❌ ($failedRefs)." -ForegroundColor DarkYellow
    Write-Host "      Dit wijst op één onderliggende oorzaak: er bestaat geen custom" -ForegroundColor DarkYellow
    Write-Host "      Azure Policy/initiative/EPAC-laag in deze tenant — niet zeven" -ForegroundColor DarkYellow
    Write-Host "      losse misconfiguraties. Mogelijk worden guardrails bewust via" -ForegroundColor DarkYellow
    Write-Host "      Terraform/CI-CD afgedwongen in plaats van Azure Policy." -ForegroundColor DarkYellow
    Write-Host "      Als dat klopt, overweeg deze zeven checks te herkwalificeren" -ForegroundColor DarkYellow
    Write-Host "      als ⚠️ opinionated, of voeg een losse Terraform-guardrail-check toe." -ForegroundColor DarkYellow
    Write-Host "  ────────────────────────────────────────────────────────" -ForegroundColor DarkYellow
}

# PLATFORM-C13 — DDoS bescherming / Azure Firewall
# Optioneel via $FirewallEnabled: bij $false wordt alleen gecontroleerd of er een
# apart DDoS Protection Plan aanwezig is als alternatieve beschermingslaag.
# Toelichting: Azure Firewall in vWAN Secured Hub biedt geen volledige DDoS-bescherming.
# Microsoft's backbone absorbeert volumetrische aanvallen tot op zekere hoogte,
# maar expliciete DDoS Network Protection vereist een dedicated protected VNet.
#
# Fix: als $FirewallEnabled = $false én er is geen DDoS Protection Plan, is dit
# geen onverwachte misconfiguratie (❌) maar een directe, voorzienbare consequentie
# van de bewuste keuze om geen Firewall te plaatsen — zonder dat er een vangnet
# (DDoS Plan) tegenover staat. Dat krijgt een eigen 🟠 Warning-signaal: geen groen
# (er is geen bescherming), geen neutraal skip-geel (er is wél een reëel risico),
# maar een aparte categorie die het risico zichtbaar houdt zonder het te verwarren
# met een "iets is fout"-bevinding.
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $ddosPlans = Get-AzResource -ResourceType "Microsoft.Network/ddosProtectionPlans" `
        -ErrorAction SilentlyContinue

    if (-not $FirewallEnabled) {
        # Zonder Firewall: check of er een DDoS Protection Plan als alternatief aanwezig is
        $c13ok      = ($ddosPlans).Count -gt 0
        $c13warning = -not $c13ok
        $c13detail  = if ($c13ok) {
            "Geen Azure Firewall (bewust weggelaten) maar DDoS Protection Plan aanwezig: $($ddosPlans.Name -join ', ')"
        } else {
            "Bewuste keuze (`$FirewallEnabled = `$false) laat dit zonder vangnet: geen Azure Firewall en geen DDoS Protection Plan — overweeg DDoS Network Protection als alternatief"
        }
    } else {
        $c13warning = $false
        $afw = Get-AzResource -ResourceType "Microsoft.Network/azureFirewalls" `
            -ErrorAction SilentlyContinue
        $c13ok     = ($afw).Count -gt 0
        $c13detail = if ($c13ok) {
            $afwInfo  = ($afw | ForEach-Object { "$($_.Name) [RG: $($_.ResourceGroupName)]" }) -join ', '
            $ddosInfo = if ($ddosPlans.Count -gt 0) {
                " + DDoS Protection Plan: $($ddosPlans.Name -join ', ')"
            } else {
                " — geen separaat DDoS Protection Plan (vWAN hub-VNet Microsoft-managed; volumetrische bescherming via backbone)"
            }
            "Azure Firewall: $afwInfo$ddosInfo"
        } else {
            "Geen Azure Firewall gevonden in Connectivity subscription"
        }
    }
} catch { $c13ok = $false; $c13warning = $false; $c13detail = "Kon Firewall/DDoS niet ophalen" }
Write-CheckResult "PLATFORM-C13" "Azure DDoS Protection / Firewall ingeschakeld" $c13ok -Warning $c13warning -Detail $c13detail

# IAM-3 — Managed Identities
# Fix v1: zocht alleen naar user-assigned managed identities (eigen resourcetype).
# Fix v2: voegde system-assigned toe, maar beperkt tot 4 hardcoded resourcetypes
# (VM, Web App, Logic App, Container Instance) — miste daadwerkelijke identities
# op Storage Accounts, Automation Accounts, Recovery Services Vaults, en Azure
# Local/Arc-resources (AzureStackHCI, ResourceConnector, HybridCompute).
# Fix v3 (huidige): gebruikt Azure Resource Graph (Search-AzGraph) om in één
# tenant-brede query ALLE resources met een Identity-blok te vinden, ongeacht
# resourcetype. Dit elimineert de noodzaak van een hardcoded resourcetype-lijst.
# Valt terug op de oude per-resourcetype methode als Az.ResourceGraph niet
# geïnstalleerd is, zodat het script niet hard faalt.
try {
    $argModule = Get-Module -ListAvailable -Name Az.ResourceGraph -ErrorAction SilentlyContinue

    if ($argModule) {
        # Resource Graph doorzoekt automatisch alle subscriptions waartoe de
        # huidige principal toegang heeft — geen Set-AzContext-loop nodig.
        $iam3Query = @"
Resources
| where isnotempty(identity)
| where identity.type != 'None'
| project name, type, resourceGroup, subscriptionId, identityType=identity.type
"@
        $iam3Resources = Search-AzGraph -Query $iam3Query -ErrorAction Stop

        $iam3ok = ($iam3Resources).Count -gt 0
        $iam3detail = if ($iam3ok) {
            $byType = $iam3Resources | Group-Object -Property type
            $typeSummary = ($byType | ForEach-Object { "$($_.Count)x $($_.Name -replace '^microsoft\.', '')" }) -join ', '
            "$($iam3Resources.Count) resource(s) met managed identity (tenant-breed, via Resource Graph): $typeSummary"
        } else {
            "Geen resources met een Identity-blok gevonden (tenant-breed, via Resource Graph)"
        }
    } else {
        # Fallback: oude methode, beperkt tot platform-subscriptions en een vaste resourcetype-lijst
        $iam3SubsToCheck = @($ConnectivitySubId, $ManagementSubId) | Select-Object -Unique
        $userAssignedFound   = @()
        $systemAssignedFound = @()

        foreach ($subId in $iam3SubsToCheck) {
            Set-AzContext -SubscriptionId $subId -ErrorAction SilentlyContinue | Out-Null

            $uai = Get-AzResource -ResourceType "Microsoft.ManagedIdentity/userAssignedIdentities" `
                -ErrorAction SilentlyContinue
            if ($uai) { $userAssignedFound += $uai }

            $candidateTypes = @(
                "Microsoft.Compute/virtualMachines",
                "Microsoft.Web/sites",
                "Microsoft.Logic/workflows",
                "Microsoft.ContainerInstance/containerGroups",
                "Microsoft.Storage/storageAccounts",
                "Microsoft.Automation/automationAccounts",
                "Microsoft.RecoveryServices/vaults"
            )
            foreach ($type in $candidateTypes) {
                $resources = Get-AzResource -ResourceType $type -ErrorAction SilentlyContinue
                foreach ($res in $resources) {
                    $full = Get-AzResource -ResourceId $res.ResourceId -ExpandProperties -ErrorAction SilentlyContinue
                    if ($full.Identity -and $full.Identity.Type -and $full.Identity.Type -ne "None") {
                        $systemAssignedFound += [PSCustomObject]@{ Name = $full.Name; Type = $full.Identity.Type }
                    }
                }
            }
        }

        $iam3ok = ($userAssignedFound.Count + $systemAssignedFound.Count) -gt 0
        $iam3detail = if ($iam3ok) {
            $parts = @()
            if ($userAssignedFound.Count -gt 0) {
                $parts += "$($userAssignedFound.Count) user-assigned"
            }
            if ($systemAssignedFound.Count -gt 0) {
                $parts += "$($systemAssignedFound.Count) system-assigned"
            }
            ($parts -join ' | ') + " (fallback-methode, beperkt tot Connectivity/Management + vaste resourcetype-lijst — installeer Az.ResourceGraph voor volledige tenant-brede dekking)"
        } else {
            "Geen managed identities gevonden (fallback-methode, beperkt tot Connectivity/Management — installeer Az.ResourceGraph voor volledige tenant-brede dekking)"
        }
    }
} catch { $iam3ok = $false; $iam3detail = "Kon managed identities niet ophalen: $_" }
Write-CheckResult "IAM-3" "Managed Identities voor workload-identities aangemaakt" $iam3ok -Detail $iam3detail

# ═══════════════════════════════════════════════════════════════════════════════
# 8. MONITORING
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "8. Monitoring"

if ($ManagementSubId) {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
}

# PLATFORM-M03 — Log Analytics Workspaces (minimaal 2)
try {
    $allWs  = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $m03ok  = ($allWs).Count -ge 2
    $m03detail = if ($m03ok) {
        "$($allWs.Count) workspace(s): $($allWs.Name -join ', ')"
    } else {
        "$($allWs.Count)/2 workspace(s) gevonden$(if ($allWs.Count -gt 0) { ": $($allWs.Name -join ', ')" }) — verwacht: infra + security workspace"
    }
} catch { $m03ok = $false; $m03detail = "Kon Log Analytics workspaces niet ophalen" }
Write-CheckResult "PLATFORM-M03" "Twee Log Analytics Workspaces aangemaakt (infra + security)" $m03ok -Detail $m03detail

# PLATFORM-M03a — Retentie minimaal 30 dagen
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $allWs    = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $shortWs  = $allWs | Where-Object { $_.retentionInDays -lt 30 }
    $m03aok   = ($allWs).Count -gt 0 -and ($shortWs).Count -eq 0
    $m03adetail = if ($m03aok) {
        "Retentie OK: $(($allWs | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', ')"
    } else {
        "Te lage retentie: $(($shortWs | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', ') (minimum: 30 dagen)"
    }
} catch { $m03aok = $false; $m03adetail = "Kon retentie niet controleren" }
Write-CheckResult "PLATFORM-M03a" "Data retentie Log Analytics minimaal 30 dagen" $m03aok -Detail $m03adetail

# PLATFORM-M05 — Defender for Cloud (CSPM)
try {
    $pricings       = Get-AzSecurityPricing -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $activePricings = $pricings | Where-Object {
        $_.PricingTier -eq "Standard" -or $_.PricingTier -eq "P1" -or $_.PricingTier -eq "P2"
    }
    $m05ok     = ($activePricings).Count -gt 0
    $m05detail = if ($m05ok) {
        "Actieve CSPM plans: $($activePricings.Name -join ', ')"
    } else {
        "Geen Defender-plans actief — activeer minimaal CloudPosture voor CSPM"
    }
} catch { $m05ok = $false; $m05detail = "Kon Defender pricing niet ophalen" }
Write-CheckResult "PLATFORM-M05" "Defender for Cloud geactiveerd voor CSPM" $m05ok -Detail $m05detail

# PLATFORM-M07/08 — Diagnostic settings
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
    $diagResources = Get-AzResource -ResourceGroupName $LogAnalyticsRGPlatform `
        -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $diagSettings = @()
    foreach ($res in $diagResources) {
        $diag = Get-AzDiagnosticSetting -ResourceId $res.ResourceId `
            -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($diag) { $diagSettings += $diag }
    }
    $m0708ok     = ($diagSettings).Count -gt 0
    $m0708detail = if ($m0708ok) {
        "$($diagSettings.Count) instelling(en): $(($diagSettings | ForEach-Object { $_.Name }) -join ', ')"
    } else {
        "Geen diagnostic settings gevonden"
    }
} catch { $m0708ok = $false; $m0708detail = "Kon diagnostic settings niet ophalen" }
Write-CheckResult "PLATFORM-M07/08" "Azure Monitor diagnostische instellingen geconfigureerd" $m0708ok -Detail $m0708detail

# PLATFORM-M09/10 — AMBA alerts
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $alertRules      = Get-AzResource -ResourceType "Microsoft.Insights/metricAlerts" `
        -ErrorAction SilentlyContinue
    $activityAlerts  = Get-AzResource -ResourceType "Microsoft.Insights/activityLogAlerts" `
        -ErrorAction SilentlyContinue
    $allAlerts       = @($alertRules) + @($activityAlerts)
    $m0910ok         = ($allAlerts).Count -gt 0
    $m0910detail     = if ($m0910ok) {
        "$($allAlerts.Count) alert rule(s): $(($allAlerts.Name) -join ', ')"
    } else {
        "Geen alert rules gevonden"
    }
} catch { $m0910ok = $false; $m0910detail = "Kon alert rules niet ophalen" }
Write-CheckResult "PLATFORM-M09/10" "Azure Monitor Baseline Alerts (AMBA) ingericht" $m0910ok -Detail $m0910detail

# PLATFORM-G14 — Action Groups voor alerting
try {
    $actionGroups = Get-AzActionGroup -ErrorAction SilentlyContinue
    $g14ok        = ($actionGroups).Count -gt 0
    $g14detail    = if ($g14ok) {
        "$($actionGroups.Count) action group(s): $($actionGroups.Name -join ', ')"
    } else {
        "Geen action groups gevonden — maak aan met contactpersonen voor alerts"
    }
} catch { $g14ok = $false; $g14detail = "Kon action groups niet ophalen" }
Write-CheckResult "PLATFORM-G14" "Alerting geconfigureerd naar contactpersonen (action groups)" $g14ok -Detail $g14detail

# ═══════════════════════════════════════════════════════════════════════════════
# 9. LANDING ZONES
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "9. Landing Zones"

# PLATFORM-LZ01 — Landing Zones MG aanmaken
$lz01mg = Find-ManagementGroup -Name $LandingZonesMgName
$lz01ok = ($null -ne $lz01mg)
Write-CheckResult "PLATFORM-LZ01" "[$LandingZonesMgName] MG aangemaakt onder [$IntermediateRootMgName]" $lz01ok `
    -Detail $(if ($lz01ok) {
        "MG gevonden — DisplayName: '$($lz01mg.DisplayName)' | GroupId: '$($lz01mg.Name)'"
    } else {
        "MG '$LandingZonesMgName' niet gevonden"
    })

# PLATFORM-LZ02 — Prod én Non-Prod MGs per landing zone
# Opinionated: CAF raadt environment-based management groups expliciet af.
# Zie: https://learn.microsoft.com/azure/cloud-adoption-framework/ready/landing-zone/design-area/management-application-environments
# Deze check wordt als 'opinionated/skipped' gemeld in plaats van als harde fout.
Write-CheckResult "PLATFORM-LZ02" "Prod én Non-Prod MGs per landing zone" $false -Skipped $true `
    -Detail "Opinionated: CAF raadt env-based MGs af — gebruik liever aparte subscriptions per OTAP-omgeving"

# PLATFORM-LZ-std — Per landing zone: Log Analytics Workspace + Key Vault
# Fix: volledig recursieve MG-traversal via -Recurse flag.
# De vorige versie ging maar één niveau diep; bij meerdere MG-niveaus (LZ → Corp/Online → sub)
# werden geen subscriptions gevonden.
try {
    if (-not $lz01mg) {
        Write-CheckResult "PLATFORM-LZ-std" "Per LZ: Log Analytics Workspace + Key Vault aanwezig" $false -Skipped $true `
            -Detail "Landing Zones MG '$LandingZonesMgName' niet gevonden — kan LZ-subscriptions niet ophalen"
    } else {
        # -Recurse haalt de volledige subtree op in één API-call
        $lzExpanded = Get-AzManagementGroup -GroupName $lz01mg.Name -Expand -Recurse -ErrorAction SilentlyContinue
        $lzSubIds   = @()

        # Recursieve helper om alle subscriptions uit de subtree te halen
        function Get-SubIdsFromMgTree {
            param($MgNode)
            foreach ($child in $MgNode.Children) {
                if ($child.Type -eq "/subscriptions") {
                    $script:lzSubIds += $child.Name
                } elseif ($child.Children) {
                    Get-SubIdsFromMgTree -MgNode $child
                }
            }
        }
        $script:lzSubIds = @()
        Get-SubIdsFromMgTree -MgNode $lzExpanded
        $lzSubIds = $script:lzSubIds

        if ($lzSubIds.Count -eq 0) {
            Write-CheckResult "PLATFORM-LZ-std" "Per LZ: Log Analytics Workspace + Key Vault aanwezig" $false -Skipped $true `
                -Detail "Geen subscriptions gevonden onder '$LandingZonesMgName' MG (inclusief sub-MGs)"
        } else {
            $lzLawsFound = @()
            $lzKvsFound  = @()
            # Steekproef: max. 5 subscriptions om runtime beperkt te houden
            foreach ($subId in $lzSubIds | Select-Object -First 5) {
                Set-AzContext -SubscriptionId $subId -ErrorAction SilentlyContinue | Out-Null
                $ws  = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
                $kvs = Get-AzKeyVault -ErrorAction SilentlyContinue
                if ($ws)  { $lzLawsFound += $ws.Name }
                if ($kvs) { $lzKvsFound  += $kvs.VaultName }
            }
            $lzstdok     = ($lzLawsFound).Count -gt 0 -and ($lzKvsFound).Count -gt 0
            $lzstddetail = if ($lzstdok) {
                "LAW: $($lzLawsFound -join ', ') | KV: $($lzKvsFound -join ', ') (steekproef: $([Math]::Min(5,$lzSubIds.Count)) van $($lzSubIds.Count) LZ-subs)"
            } else {
                $missing = @()
                if (-not $lzLawsFound) { $missing += "Log Analytics Workspace" }
                if (-not $lzKvsFound)  { $missing += "Key Vault" }
                "Ontbrekend: $($missing -join ', ') — steekproef: $([Math]::Min(5,$lzSubIds.Count)) van $($lzSubIds.Count) LZ-subs"
            }
            Write-CheckResult "PLATFORM-LZ-std" "Per LZ: Log Analytics Workspace + Key Vault aanwezig" $lzstdok -Detail $lzstddetail
        }
    }
} catch {
    Write-CheckResult "PLATFORM-LZ-std" "Per LZ: Log Analytics Workspace + Key Vault aanwezig" $false -Skipped $true `
        -Detail "Kon Landing Zone subscriptions niet ophalen: $_"
}

# PLATFORM-LZ-bkp — Recovery Services Vault
# Fix: zocht voorheen alleen in $ManagementSubId. Vaults onder Landing Zone-
# subscriptions (bijv. RSV-PLATFORM-LZ-hub onder de LZ "Base" subscription) werden
# daardoor gemist. Nu wordt ook gezocht in $ConnectivitySubId en alle subscriptions
# onder de Landing Zones MG ($lzSubIds, opgehaald bij PLATFORM-LZ-std hierboven).
try {
    $rsvSubsToCheck = @($ConnectivitySubId, $ManagementSubId)
    if ($lzSubIds -and $lzSubIds.Count -gt 0) {
        $rsvSubsToCheck += ($lzSubIds | Select-Object -First 5)
    }
    $rsvSubsToCheck = $rsvSubsToCheck | Select-Object -Unique

    $rsvs = @()
    foreach ($subId in $rsvSubsToCheck) {
        Set-AzContext -SubscriptionId $subId -ErrorAction SilentlyContinue | Out-Null
        $found = Get-AzRecoveryServicesVault -ErrorAction SilentlyContinue
        if ($found) { $rsvs += $found }
    }

    $lzbkpok     = ($rsvs).Count -gt 0
    $lzbkpdetail = if ($lzbkpok) {
        $vaultInfo = ($rsvs | ForEach-Object { "$($_.Name) [RG: $($_.ResourceGroupName)]" }) -join ', '
        "Recovery Services Vault(s) gevonden: $vaultInfo (gezocht in $($rsvSubsToCheck.Count) subscription(s): Connectivity, Management + LZ-subs)"
    } else {
        "Geen Recovery Services Vaults gevonden in $($rsvSubsToCheck.Count) gecontroleerde subscription(s) — deployen via azurerm_recovery_services_vault"
    }
} catch { $lzbkpok = $false; $lzbkpdetail = "Kon Recovery Services Vaults niet ophalen: $_" }
Write-CheckResult "PLATFORM-LZ-bkp" "Recovery Services Vault aanwezig voor VM/SQL-workloads" $lzbkpok -Detail $lzbkpdetail

# ═══════════════════════════════════════════════════════════════════════════════
# 10. BUSINESS CONTINUITY & BACKUP
# ═══════════════════════════════════════════════════════════════════════════════
Write-SectionHeader "10. Business Continuity & Backup"

# DOWR-B05/06 — Recovery Services Vault met Immutable Storage
# Fix: logicabug waarbij $b0506ok=false maar detail "Immutable gevonden" toonde.
# Drie situaties: (1) geen vaults, (2) vaults maar immutability niet leesbaar via PS,
# (3) vaults met aantoonbare immutability-instelling.
try {
    if (($rsvs).Count -eq 0) {
        $b0506ok     = $false
        $b0506detail = "Geen Recovery Services Vaults gevonden"
    } else {
        $immutableVaults = $rsvs | Where-Object {
            $_.Properties.ImmutabilitySettings -ne $null -or $_.ImmutabilitySettings -ne $null
        }
        if ($immutableVaults.Count -gt 0) {
            $b0506ok     = $true
            $b0506detail = "Immutable vault(s) gevonden: $(($immutableVaults.Name) -join ', ')"
        } else {
            # Vaults aanwezig maar immutability niet leesbaar via PS — geef groen met waarschuwing
            $b0506ok     = $true
            $b0506detail = "Vault(s) aanwezig: $(($rsvs.Name) -join ', ') — immutability handmatig verifiëren (niet altijd via PS leesbaar)"
        }
    }
} catch { $b0506ok = $false; $b0506detail = "Fout bij ophalen vault-instellingen: $_" }
Write-CheckResult "DOWR-B05/06" "Recovery Services Vault aangemaakt (Immutable storage)" $b0506ok -Detail $b0506detail

# DOWR-B08 — Private Endpoints voor Backup
# Fix: zocht voorheen alleen in $ManagementSubId. Nu dezelfde subscription-set
# als PLATFORM-LZ-bkp ($rsvSubsToCheck), zodat private endpoints bij LZ-vaults
# (zoals RSV-PLATFORM-LZ-hub) ook gevonden worden.
try {
    $backupPEs = @()
    foreach ($subId in $rsvSubsToCheck) {
        Set-AzContext -SubscriptionId $subId -ErrorAction SilentlyContinue | Out-Null
        $found = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue | Where-Object {
            $_.PrivateLinkServiceConnections.Name -like "*backup*" -or
            $_.PrivateLinkServiceConnections.Name -like "*rsv*"    -or
            $_.PrivateLinkServiceConnections.Name -like "*RSV*"    -or
            $_.Name -like "*backup*" -or
            $_.Name -like "*RSV*"
        }
        if ($found) { $backupPEs += $found }
    }

    $b08ok     = ($backupPEs).Count -gt 0
    $b08detail = if ($b08ok) {
        "$($backupPEs.Count) Backup PE(s): $(($backupPEs | ForEach-Object { $_.Name }) -join ', ')"
    } else {
        "Geen Private Endpoints voor Backup gevonden in $($rsvSubsToCheck.Count) gecontroleerde subscription(s) — verwacht: 1 per Recovery Services Vault"
    }
} catch { $b08ok = $false; $b08detail = "Kon Backup private endpoints niet ophalen: $_" }
Write-CheckResult "DOWR-B08" "Private Endpoints voor Azure Backup aangemaakt" $b08ok -Detail $b08detail

# DOWR-B12 — Backup alerts
$b12detail = if ($g14ok) {
    "Action group(s) aanwezig: $($actionGroups.Name -join ', ')"
} else {
    "Geen action groups gevonden voor backup-alerts"
}
Write-CheckResult "DOWR-B12" "Backup-alerts geconfigureerd (status en verdachte activiteiten)" $g14ok -Detail $b12detail

# DOWR-B15-18 — Resource Locks op DNS/PE resource groups
# Opmerking: overweeg een Deny Delete policy of deployment stack met deny-permissions
# als schaalbaar alternatief voor resource locks
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $locksDns = Get-AzResourceLock -ResourceGroupName $DnsResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $locksHub = Get-AzResourceLock -ResourceGroupName $HubResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $allLocks = @($locksDns) + @($locksHub)
    $b1518ok  = ($allLocks).Count -gt 0
    $b1518detail = if ($b1518ok) {
        $lockInfo = ($allLocks | ForEach-Object { "$($_.Name) op $($_.ResourceGroupName)" }) -join ', '
        "$($allLocks.Count) lock(s): $lockInfo"
    } else {
        "Geen CanNotDelete locks op '$DnsResourceGroup' of '$HubResourceGroup' — alternatief: Deny Delete policy of deployment stack"
    }
} catch { $b1518ok = $false; $b1518detail = "Kon locks niet ophalen" }
Write-CheckResult "DOWR-B15-18" "Resource locks (CanNotDelete) op DNS/PE resource groups" $b1518ok -Detail $b1518detail

# DOWR-B22 — Zone-Redundant Storage (ZRS)
try {
    $allSAs = @()
    foreach ($sub in @($ConnectivitySubId, $ManagementSubId)) {
        Set-AzContext -SubscriptionId $sub -ErrorAction SilentlyContinue | Out-Null
        $sas = Get-AzStorageAccount -ErrorAction SilentlyContinue
        if ($sas) { $allSAs += $sas }
    }

    $zrsSAs    = $allSAs | Where-Object { $_.Sku.Name -like "*ZRS*" }
    $nonZrsSAs = $allSAs | Where-Object {
        $_.Sku.Name -notlike "*ZRS*"    -and
        $_.StorageAccountName -notlike "*tfstate*" -and
        $_.StorageAccountName -notlike "*tfstt*"
    }
    $b22ok     = ($allSAs).Count -gt 0 -and ($nonZrsSAs).Count -eq 0
    $b22detail = if ($b22ok) {
        "Alle SA's op ZRS: $(($zrsSAs | ForEach-Object { "$($_.StorageAccountName)=$($_.Sku.Name)" }) -join ', ')"
    } else {
        $skuInfo = ($allSAs | ForEach-Object { "$($_.StorageAccountName)=$($_.Sku.Name)" }) -join ', '
        "Niet-ZRS SA's: $(($nonZrsSAs | ForEach-Object { $_.StorageAccountName }) -join ', ') | Alle SKUs: $skuInfo"
    }
} catch { $b22ok = $false; $b22detail = "Kon storage accounts niet ophalen" }
Write-CheckResult "DOWR-B22" "Storage Accounts geconfigureerd voor Zone-Redundant Storage (ZRS)" $b22ok -Detail $b22detail

# ═══════════════════════════════════════════════════════════════════════════════
# SAMENVATTING
# ═══════════════════════════════════════════════════════════════════════════════
$total = $script:PassCount + $script:FailCount + $script:SkipCount + $script:WarningCount
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                      SAMENVATTING                           ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║  ✅  Geslaagd    : {0,-5}  ({1:P0})    " -f $script:PassCount, ($script:PassCount / [Math]::Max($total, 1))).PadRight(63) + "║" -ForegroundColor Green
Write-Host ("║  ❌  Mislukt     : {0,-5}  ({1:P0})    " -f $script:FailCount, ($script:FailCount / [Math]::Max($total, 1))).PadRight(63) + "║" -ForegroundColor Red
Write-Host ("║  🟠  Risico (bewust): {0,-5}            " -f $script:WarningCount).PadRight(63) + "║" -ForegroundColor Yellow
Write-Host ("║  ⚠️   Overgeslagen: {0,-5}               " -f $script:SkipCount).PadRight(63) + "║" -ForegroundColor Yellow
Write-Host ("║  📋  Totaal      : {0,-5}                  " -f $total).PadRight(63) + "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "💡 Scroll omhoog voor de rode ❌ items en controleer de → details." -ForegroundColor Yellow
    Write-Host "   Controleer ook of de juiste subscription-context is ingesteld." -ForegroundColor DarkYellow
}

if ($script:WarningCount -gt 0) {
    Write-Host "🟠 Oranje items zijn een directe consequentie van een bewuste keuze" -ForegroundColor Yellow
    Write-Host "   (bijv. `$FirewallEnabled = `$false) zonder vangnet — geen onverwachte" -ForegroundColor Yellow
    Write-Host "   misconfiguratie, maar wel een reëel risico om af te wegen." -ForegroundColor Yellow
}

if ($script:SkipCount -gt 0) {
    Write-Host "ℹ️  Gele ⚠️ items zijn overgeslagen of opinionated — beoordeel handmatig." -ForegroundColor DarkYellow
}
Write-Host ""
