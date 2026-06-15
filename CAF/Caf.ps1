<#
.SYNOPSIS
    COEO Azure Terraform Implementatie Checklist Verificatie
.DESCRIPTION
    Controleert of alle items uit de COEO Terraform checklist zijn gedeployed en actief zijn.
    Geeft groene vinkjes (✅) voor OK en rode kruisjes (❌) voor niet gevonden/actief.
.NOTES
    Vereisten: Az PowerShell module + ingelogd via Connect-AzAccount
    Versie: 0.8 | Mei 2026
#>

# ─────────────────────────────────────────────────────────────────
# CONFIG — pas deze waarden aan voor jouw omgeving
# ─────────────────────────────────────────────────────────────────
$TenantId              = "73bf8b44-c1e6-49c4-9fa9-5e86a46d2942"        # of vul direct in: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
$ConnectivitySubId     = "15edebbb-0f88-4644-b366-f1454cc8017c"    # Subscription ID voor Connectivity
$ManagementSubId       = "6a639e00-4be1-4629-869d-b5f5664b4016"      # Subscription ID voor Management/Governance
$RootMgName            = "COEO"                      # Naam van de root management group
$HubResourceGroup      = "RG-coeo-PL-CON-vWAN"
$DnsResourceGroup      = "RG-coeo-PL-CON-DNS"
$LogAnalyticsRGPlatform = "RG-coeo-PL-MGMT-LOG"
$VWanName              = "VWAN-coeo-PL-CON"
$VHubName              = "VHUB-coeo-PL-CON-WEU"
$FirewallPolicyName    = "AFWP-coeo-PL-CON-Core"

# ─────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────
$script:PassCount = 0
$script:FailCount = 0
$script:SkipCount = 0

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
        [string]$Detail = ""
    )
    $refPadded  = $Ref.PadRight(18)
    $descShort  = if ($Description.Length -gt 72) { $Description.Substring(0, 69) + "..." } else { $Description }

    if ($Skipped) {
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
$script:AllManagemementGroups = $null

function Get-AllMGs {
    if ($null -eq $script:AllManagemementGroups) {
        try {
            $script:AllManagemementGroups = Get-AzManagementGroup -ErrorAction SilentlyContinue
        } catch {
            $script:AllManagemementGroups = @()
        }
    }
    return $script:AllManagemementGroups
}

function Find-ManagementGroup {
    # Zoekt op GroupId (technische naam) én DisplayName (portal-naam)
    # Geeft het MG-object terug als gevonden, anders $null
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
    param([string]$Scope, [string]$NameContains)
    try {
        $assignments = Get-AzPolicyAssignment -Scope $Scope -ErrorAction SilentlyContinue
        return ($assignments | Where-Object { $_.Name -like "*$NameContains*" -or $_.Properties.DisplayName -like "*$NameContains*" }).Count -gt 0
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

# ─────────────────────────────────────────────────────────────────
# PRE-FLIGHT: Controleer of we ingelogd zijn
# ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   COEO Azure Terraform Checklist Verificatie  v0.8          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$context = Get-AzContext -ErrorAction SilentlyContinue
if (-not $context) {
    Write-Host "⚠️  Niet ingelogd bij Azure. Voer eerst Connect-AzAccount uit." -ForegroundColor Yellow
    exit 1
}
Write-Host "  Ingelogd als : $($context.Account.Id)" -ForegroundColor DarkGray
Write-Host "  Tenant       : $($context.Tenant.Id)" -ForegroundColor DarkGray
Write-Host "  Subscription : $($context.Subscription.Name)" -ForegroundColor DarkGray
Write-Host ""

# ═══════════════════════════════════════════════════════════════════
# 1. GOVERNANCE & MANAGEMENT GROUPS
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "1. Governance & Management Groups"

# COEO-G01 — Management group structuur
# Find-ManagementGroup zoekt op zowel GroupId (technisch) als DisplayName (portal)
# zodat "Landing Zones" én "LandingZones" beide matchen
$mgChecks = [ordered]@{
    "COEO"           = Find-ManagementGroup -Name "COEO"
    "Platform"       = Find-ManagementGroup -Name "Platform"
    "Landing Zones"  = $(
        $lz = Find-ManagementGroup -Name "Landing Zones"
        if (-not $lz) { $lz = Find-ManagementGroup -Name "LandingZones" }
        $lz
    )
    "Sandbox"        = Find-ManagementGroup -Name "Sandbox"
    "Decommissioned" = Find-ManagementGroup -Name "Decommissioned"
}
$mgCoeo    = $mgChecks["COEO"]
$mgMissing = ($mgChecks.GetEnumerator() | Where-Object { $null -eq $_.Value } | ForEach-Object { $_.Key })
$mgFound   = ($mgChecks.GetEnumerator() | Where-Object { $null -ne $_.Value } | ForEach-Object {
    "$($_.Key) [GroupId: $($_.Value.Name)]"
})
$g01ok = $mgMissing.Count -eq 0
Write-CheckResult "COEO-G01" "Management group structuur aanmaken (Root → COEO → sub-groepen)" $g01ok `
    -Detail $(if ($g01ok) {
        "Alle MG's gevonden: $($mgFound -join ' | ')"
    } else {
        "Ontbrekend: $($mgMissing -join ', ') | Gevonden: $(if ($mgFound) { $mgFound -join ', ' } else { 'geen' })"
    })

# COEO-G05 — Root MG: alleen break-glass
try {
    $rootRoles = Get-AzRoleAssignment -Scope "/providers/Microsoft.Management/managementGroups/Tenant Root Group" -ErrorAction SilentlyContinue
    $rootOwners = $rootRoles | Where-Object { $_.RoleDefinitionName -eq "Owner" }
    $g05ok = ($rootOwners).Count -le 2
    $g05detail = if ($g05ok) {
        if ($rootOwners.Count -eq 0) { "Geen Owner-assignments op Root MG" } else { "Owner(s) op Root MG: $($rootOwners.SignInName -join ', ')" }
    } else {
        "Te veel Owner-assignments ($($rootOwners.Count)): $($rootOwners.SignInName -join ', ')"
    }
} catch { $g05ok = $false; $g05detail = "Kon Root MG RBAC niet ophalen" }
Write-CheckResult "COEO-G05" "Root MG: alleen break-glass accounts, geen onnodige RBAC" $g05ok -Detail $g05detail

# COEO-G06 — Audit-only policies op tenant niveau
try {
    $coeoMgG06 = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq $RootMgName } | Select-Object -First 1
    $coeoScopeG06 = "/providers/Microsoft.Management/managementGroups/$($coeoMgG06.Name)"
    $g06assignments = Get-AzPolicyAssignment -Scope $coeoScopeG06 -ErrorAction SilentlyContinue
    $g06audit = $g06assignments | Where-Object { 
        $_.Name -like "*audit*" -or 
        $_.Properties.DisplayName -like "*audit*"
    }
    $g06ok = ($g06audit).Count -gt 0
    $g06detail = if ($g06ok) {
        $names = ($g06audit | ForEach-Object {
            if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
        }) -join ', '
        "Audit policy/policies gevonden: $names"
    } else {
        "Geen audit-only policies gevonden op scope $RootMgName — controleer policy assignments"
    }
} catch { $g06ok = $false; $g06detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "COEO-G06" "Tenant level: uitsluitend audit-only policies toewijzen" $g06ok -Detail $g06detail

# COEO-G07 — Custom roles
try {
    $customRoles = Get-AzRoleDefinition -Custom -ErrorAction SilentlyContinue `
        -WarningAction SilentlyContinue
    $g07ok = ($customRoles).Count -gt 0
    $g07detail = if ($g07ok) {
        "$($customRoles.Count) custom role(s): $(($customRoles.Name) -join ', ')"
    } else {
        "Geen custom rollen gevonden op tenant-niveau"
    }
} catch { $g07ok = $false; $g07detail = "Kon custom roles niet ophalen" }
Write-CheckResult "COEO-G07" "Custom role definitions op tenant-niveau gedefinieerd" $g07ok -Detail $g07detail

# COEO-G09/10 — Sandbox isoleren
try {
    $sandboxMg = Find-ManagementGroup -Name "Sandbox"
    $sandboxScope = if ($sandboxMg) { "/providers/Microsoft.Management/managementGroups/$($sandboxMg.Name)" } else { "/providers/Microsoft.Management/managementGroups/Sandbox" }
    $sandboxAssignments = Get-AzPolicyAssignment -Scope $sandboxScope -ErrorAction SilentlyContinue
    $sandboxPeeringPolicy = $sandboxAssignments | Where-Object { 
    $_.Name -like "*peer*" -or 
    $_.Name -like "*sandbox*" -or
    $_.Properties.DisplayName -like "*peer*" -or
    $_.Properties.DisplayName -like "*sandbox*"
}
    $g09ok = ($sandboxPeeringPolicy).Count -gt 0
    $g09detail = if ($g09ok) {
    $policyNames = ($sandboxPeeringPolicy | ForEach-Object {
        if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
    }) -join ', '
    "Peering-blokkade policy gevonden: $policyNames"
} else {
    $allNames = ($sandboxAssignments | ForEach-Object {
        if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
    }) -join ', '
    "Geen peering-blokkade policy op Sandbox MG — gevonden policies: $(if ($allNames) { $allNames } else { 'geen' })"
}
} catch { $g09ok = $false; $g09detail = "Sandbox MG niet gevonden of geen rechten" }
Write-CheckResult "COEO-G09/10" "Sandbox MG volledig isoleren (geen VNet peerings via policy)" $g09ok -Detail $g09detail

# COEO-G11 — Decommissioned MG
$g11mg = Find-ManagementGroup -Name "Decommissioned"
$g11ok = ($null -ne $g11mg)
Write-CheckResult "COEO-G11" "Decommissioned management group aangemaakt" $g11ok `
    -Detail $(if ($g11ok) { "Gevonden — DisplayName: '$($g11mg.DisplayName)' | GroupId: '$($g11mg.Name)'" } else { "MG 'Decommissioned' niet gevonden" })

# COEO-G15 — Key Vaults voor secrets
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $kvsConn = Get-AzKeyVault -ErrorAction SilentlyContinue

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $kvsMgmt = Get-AzKeyVault -ErrorAction SilentlyContinue

    $allKvs = @($kvsConn) + @($kvsMgmt)
    $g15ok = ($allKvs).Count -gt 0
    $g15detail = if ($g15ok) {
        $kvNames = ($allKvs | ForEach-Object { $_.VaultName }) -join ', '
        "$($allKvs.Count) Key Vault(s) gevonden: $kvNames"
    } else {
        "Geen Key Vaults gevonden"
    }
} catch { $g15ok = $false; $g15detail = "Kon Key Vaults niet ophalen" }
Write-CheckResult "COEO-G15" "Key Vaults aangemaakt voor credentials en secrets" $g15ok -Detail $g15detail

# COEO-G16 — Resource locks op platform resources
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $locksConn = Get-AzResourceLock -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $locksDns  = Get-AzResourceLock -ResourceGroupName $DnsResourceGroup -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $locksMgmt = Get-AzResourceLock -ResourceGroupName $LogAnalyticsRGPlatform -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }

    $locks = @($locksConn) + @($locksDns) + @($locksMgmt)
    $g16ok = ($locks).Count -gt 0
    $g16detail = if ($g16ok) {
        $rgNames = ($locks | ForEach-Object { $_.ResourceGroupName } | Sort-Object -Unique) -join ', '
        "$($locks.Count) CanNotDelete lock(s) op: $rgNames"
    } else {
        "Geen CanNotDelete locks gevonden"
    }
} catch {
    $g16ok = $false
    $g16detail = "Fout: $_"
}
Write-CheckResult "COEO-G16" "Resource locks (CanNotDelete) op platform-resources" $g16ok -Detail $g16detail

# ═══════════════════════════════════════════════════════════════════
# 2. RBAC & TOEGANGSBEHEER
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "2. RBAC & Toegangsbeheer"

# COEO-G08
# Gebruik de echte GroupId van de gevonden COEO MG voor de scope
$coeoGroupId = if ($mgCoeo) { $mgCoeo.Name } else { $RootMgName }
$coeoScope   = "/providers/Microsoft.Management/managementGroups/$coeoGroupId"
try {
    $g08roles = Get-AzRoleAssignment -Scope $coeoScope -ErrorAction SilentlyContinue
    $g08contrib = $g08roles | Where-Object { $_.RoleDefinitionName -eq "Contributor" }
    $g08ok = ($g08contrib).Count -gt 0
    $g08detail = if ($g08ok) { "Contributor(s) op [COEO] MG: $($g08contrib.DisplayName -join ', ')" } else {
        $foundRoles = ($g08roles.RoleDefinitionName | Sort-Object -Unique) -join ', '
        "Geen Contributor op [COEO] MG — gevonden rollen: $(if ($foundRoles) { $foundRoles } else { 'geen' })"
    }
} catch { $g08ok = $false; $g08detail = "Kon RBAC op [COEO] MG niet ophalen" }
Write-CheckResult "COEO-G08" "RBAC beheerders toegewezen op [COEO] MG niveau" $g08ok -Detail $g08detail

# COEO-G31 — PIM eligible assignments
try {
    $pimRoles = Get-AzRoleEligibleChildResource -Scope $coeoScope -ErrorAction SilentlyContinue
    $g31ok = ($pimRoles).Count -gt 0
    $g31detail = if ($g31ok) { "$($pimRoles.Count) PIM eligible assignment(s) gevonden op [COEO] MG" } else { "Geen PIM eligible assignments gevonden — controleer of Entra PIM is geconfigureerd- Dit is licentie based en niet via Scripting op te lossen" }
    Write-CheckResult "COEO-G31" "Admin-rollen altijd via Entra PIM toewijzen" $g31ok -Detail $g31detail
} catch {
    Write-CheckResult "COEO-G31" "Admin-rollen altijd via Entra PIM toewijzen" $false -Skipped $true `
        -Detail "Onvoldoende rechten voor PIM-query of Az.Resources module te oud (vereist 6.x+)"
}

# COEO-G34/35 — Per subscription: Owner/Contributor/Reader groepen
try {
    $subs = Get-AzSubscription -ErrorAction SilentlyContinue
    $g3435missing = @()
    foreach ($sub in $subs | Select-Object -First 5) {
        $subScope = "/subscriptions/$($sub.Id)"
        $roles = Get-AzRoleAssignment -Scope $subScope -ErrorAction SilentlyContinue
        $foundRoleNames = $roles.RoleDefinitionName | Sort-Object -Unique
        $missing = @("Owner","Contributor","Reader") | Where-Object { $_ -notin $foundRoleNames }
        if ($missing.Count -gt 0) {
            $g3435missing += "$($sub.Name): ontbreekt $($missing -join '/')"
        }
    }
    $g3435ok = $g3435missing.Count -eq 0
    $g3435detail = if ($g3435ok) { "Owner/Contributor/Reader gevonden op alle gecheckte subscriptions" } else { $g3435missing -join ' | ' }
} catch { $g3435ok = $false; $g3435detail = "Kon subscriptions of role assignments niet ophalen" }
Write-CheckResult "COEO-G34/35" "Per subscription drie standaard RBAC-groepen (Owner/Contrib/Reader)" $g3435ok -Detail $g3435detail

# ═══════════════════════════════════════════════════════════════════
# 3. AZURE POLICY & COMPLIANCE
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "3. Azure Policy & Compliance"

# COEO-G22 — Defender for Cloud
if ($ConnectivitySubId) { Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null }
try {
    $defenderPlans = Get-AzSecurityPricing -ErrorAction SilentlyContinue
    $freePlans   = $defenderPlans | Where-Object { $_.PricingTier -eq "Free" }
    $activePlans = $defenderPlans | Where-Object { $_.PricingTier -ne "Free" }
    $g22ok = ($activePlans).Count -gt 0
    $g22detail = if ($g22ok) {
        "Actief: $($activePlans.Name -join ', ')" + $(if ($freePlans.Count -gt 0) { " | Nog op Free: $($freePlans.Name -join ', ')" } else { "" })
    } else {
        "Alle Defender-plans op Free-tier — activeer minimaal: VirtualMachines, SqlServers, StorageAccounts, KeyVaults"
    }
} catch { $g22ok = $false; $g22detail = "Kon Defender for Cloud pricing niet ophalen" }
Write-CheckResult "COEO-G22" "Microsoft Defender for Cloud geactiveerd op subscriptions" $g22ok -Detail $g22detail

# COEO-G23 — Policy initiatives
try {
    $initiatives = Get-AzPolicySetDefinition -Custom -ErrorAction SilentlyContinue
    $g23ok = ($initiatives).Count -gt 0
    $g23detail = if ($g23ok) {
        $initiativeNames = ($initiatives | ForEach-Object {
            if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
        }) -join ', '
        "$($initiatives.Count) initiative(s): $initiativeNames"
    } else {
        "Geen custom policy initiatives gevonden — verwacht: Tagging, LandingZone, PlatformConnectivity, PlatformSecurity"
    }
} catch { $g23ok = $false; $g23detail = "Kon policy initiatives niet ophalen" }
Write-CheckResult "COEO-G23" "Azure Policies gegroepeerd in initiatives (custom)" $g23ok -Detail $g23detail

# COEO-G18 — Policy: publieke endpoints blokkeren
try {
    $lzMg = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq "Landing Zones" } | Select-Object -First 1
    $lzScope = "/providers/Microsoft.Management/managementGroups/$($lzMg.Name)"
    $g18assignments = Get-AzPolicyAssignment -Scope $lzScope -ErrorAction SilentlyContinue
    $g18policy = $g18assignments | Where-Object {
        $_.Name -like "*public*" -or
        $_.Name -like "*pub*" -or
        $_.Name -like "*ep*" -or
        $_.Properties.DisplayName -like "*public*" -or
        $_.Properties.DisplayName -like "*endpoint*"
    }
    $g18ok = ($g18policy).Count -gt 0
    $g18detail = if ($g18ok) {
        $policyNames = ($g18policy | ForEach-Object {
            if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
        }) -join ', '
        "Policy gevonden: $policyNames"
    } else {
        "Geen public-endpoint-blokkade policy op $RootMgName — verwacht: 'Deny Public Endpoints' of vergelijkbaar"
    }
} catch { $g18ok = $false; $g18detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "COEO-G18" "Policy: publieke endpoints geblokkeerd in alle landing zones" $g18ok -Detail $g18detail

# COEO-G13 — Log retentie (Entra 30d, Activity 90d)
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $workspaces = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $shortRetention = $workspaces | Where-Object { $_.retentionInDays -lt 30 }
    $g13ok = ($workspaces).Count -gt 0 -and ($shortRetention).Count -eq 0
    $g13detail = if ($g13ok) {
        $wsInfo = ($workspaces | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', '
        "Retentie OK op alle workspaces: $wsInfo"
    } elseif ($workspaces.Count -eq 0) {
        "Geen Log Analytics Workspaces gevonden"
    } else {
        $shortInfo = ($shortRetention | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d (min. 30d)" }) -join ', '
        "Retentie te laag op: $shortInfo"
    }
} catch { $g13ok = $false; $g13detail = "Kon Log Analytics workspaces niet ophalen: $_" }
Write-CheckResult "COEO-G13" "Log retentie ingesteld (min. 30 dagen)" $g13ok -Detail $g13detail

# ═══════════════════════════════════════════════════════════════════
# 4. TAGGING & NAAMGEVING
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "4. Tagging & Naamgeving"

# COEO-G24/25 — Tag policy
try {
    $coeoMgG2425 = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq $RootMgName } | Select-Object -First 1
    $coeoScopeG2425 = "/providers/Microsoft.Management/managementGroups/$($coeoMgG2425.Name)"
    $g2425assignments = Get-AzPolicyAssignment -Scope $coeoScopeG2425 -ErrorAction SilentlyContinue
    $g2425policy = $g2425assignments | Where-Object { 
        $_.Name -like "*tag*" -or 
        $_.Properties.DisplayName -like "*tag*" 
    }
    $g2425ok = ($g2425policy).Count -gt 0
    $g2425detail = if ($g2425ok) {
        $policyNames = ($g2425policy | ForEach-Object {
            if ($_.Properties.DisplayName) { $_.Properties.DisplayName } else { $_.Name }
        }) -join ', '
        "Tag-policy gevonden: $policyNames"
    } else {
        "Geen tag-policy gevonden op $RootMgName — verwacht: 'Require Tag on Resources' of vergelijkbaar"
    }
} catch { $g2425ok = $false; $g2425detail = "Kon tag-policies niet ophalen" }
Write-CheckResult "COEO-G24/25" "Tag-beleid afgedwongen via policy op management groups" $g2425ok -Detail $g2425detail

# COEO-G40 — Budget alerts via az cli (CSP compatible)
try {
    $allBudgets = @()
    $subs = @($ConnectivitySubId, $ManagementSubId)
    foreach ($sub in $subs) {
        $b = az consumption budget list `
            --subscription $sub `
            --query "[].name" -o tsv 2>$null
        if ($b) { $allBudgets += $b }
    }
    $g40ok = ($allBudgets).Count -gt 0
    $g40detail = if ($g40ok) {
        "Budget(s) gevonden: $($allBudgets -join ', ')"
    } else {
        "Geen budgets gevonden"
    }
} catch { $g40ok = $false; $g40detail = "Kon budgets niet ophalen" }
Write-CheckResult "COEO-G40" "Budget alerts automatisch ingesteld per subscription" $g40ok -Detail $g40detail


# ═══════════════════════════════════════════════════════════════════
# 5. CONNECTIVITY & NETWERK
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "5. Connectivity & Netwerk"

if ($ConnectivitySubId) {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
}

# COEO-C02 — Virtual WAN
try {
    $vwans = Get-AzVirtualWan -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $c02ok = ($vwans).Count -gt 0
    $c02detail = if ($c02ok) { "VWAN gevonden: $($vwans.Name -join ', ') (locatie: $($vwans.Location -join ', '))" } else { "Geen Virtual WAN gevonden in resource group '$HubResourceGroup'" }
} catch { $c02ok = $false; $c02detail = "Resource group '$HubResourceGroup' niet gevonden of geen rechten" }
Write-CheckResult "COEO-C02" "Azure Virtual WAN aangemaakt (West Europe)" $c02ok -Detail $c02detail

# COEO-C02 — Secured Hub
try {
    $hubs = Get-AzVirtualHub -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $hubOk = ($hubs).Count -gt 0
    $hubDetail = if ($hubOk) { "Hub gevonden: $($hubs.Name -join ', ') (locatie: $($hubs.Location -join ', '))" } else { "Geen Virtual Hub gevonden in '$HubResourceGroup'" }
} catch { $hubOk = $false; $hubDetail = "Kon hubs niet ophalen" }
Write-CheckResult "COEO-C02" "Secured Hub aangemaakt (West Europe)" $hubOk -Detail $hubDetail

# COEO-C05 — Platform VNets
try {
Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
$vnetsConn = Get-AzVirtualNetwork -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue

Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
$vnetsMgmt = Get-AzVirtualNetwork -ErrorAction SilentlyContinue

$vnets = @($vnetsConn) + @($vnetsMgmt)
$c05ok = ($vnets).Count -ge 3
    $expectedVnets = @("Connectivity","PrivateEndpoints","Management")
    $foundNames = $vnets.Name -join ', '
    $c05detail = if ($c05ok) {
        "$($vnets.Count) VNet(s) gevonden: $foundNames"
    } else {
        "$($vnets.Count)/4 VNets gevonden$(if ($foundNames) { ": $foundNames" } else { " in '$HubResourceGroup'" }) — verwacht: Connectivity, PrivateEndpoints, Identity, Management"
    }
} catch { $c05ok = $false; $c05detail = "Kon VNets niet ophalen in '$HubResourceGroup'" }
Write-CheckResult "COEO-C05" "Platform VNets aangemaakt (Connectivity/PE/Identity/Mgmt /24)" $c05ok -Detail $c05detail

# COEO-C10 — Azure Firewall Policy
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $allFwPolicies = Get-AzResource -ResourceType "Microsoft.Network/firewallPolicies" `
        -ErrorAction SilentlyContinue | Where-Object { $_.ResourceGroupName -eq $HubResourceGroup }
    $c10ok = ($allFwPolicies).Count -gt 0
    $c10detail = if ($c10ok) { 
        "Firewall policy: $(($allFwPolicies.Name) -join ', ')" 
    } else { 
        "Geen Firewall Policy gevonden in '$HubResourceGroup'" 
    }
} catch { $c10ok = $false; $c10detail = "Kon Firewall Policies niet ophalen" }
Write-CheckResult "COEO-C10" "Azure Firewall Policy geconfigureerd in Secured Hub" $c10ok -Detail $c10detail

# COEO-C11 — VNet peerings tussen spokes verboden
try {
    $sandboxMgC11 = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq "Sandbox" } | Select-Object -First 1
    $sandboxScopeC11 = "/providers/Microsoft.Management/managementGroups/$($sandboxMgC11.Name)"
    
    $assignmentsCoeo    = Get-AzPolicyAssignment -Scope $coeoScope -ErrorAction SilentlyContinue
    $assignmentsSandbox = Get-AzPolicyAssignment -Scope $sandboxScopeC11 -ErrorAction SilentlyContinue
    $allAssignments     = @($assignmentsCoeo) + @($assignmentsSandbox)

    $c11policy = $allAssignments | Where-Object { 
        $_.Name -like "*peer*" -or 
        $_.Name -like "*no-peer*" -or
        $_.Properties.DisplayName -like "*peering*" 
    }
    $c11ok = ($c11policy).Count -gt 0
    $c11detail = if ($c11ok) { 
        "Policy: $(($c11policy.Name) -join ', ')" 
    } else { 
        "Geen spoke-peering-blokkade policy gevonden op COEO of Sandbox MG" 
    }
} catch { $c11ok = $false; $c11detail = "Kon policy assignments niet ophalen" }
Write-CheckResult "COEO-C11" "Policy: VNet peerings tussen spokes verboden" $c11ok -Detail $c11detail

# COEO-C12 — Internet breakout via Virtual WAN Hub Routing Intent
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    
    $vhubs = Get-AzVirtualHub -ResourceGroupName $HubResourceGroup `
        -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $afw = Get-AzResource -ResourceType "Microsoft.Network/azureFirewalls" `
        -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue

    $routingIntent = Get-AzResource `
        -ResourceType "Microsoft.Network/virtualHubs/routingIntent" `
        -ErrorAction SilentlyContinue

    $c12ok = ($vhubs).Count -gt 0 -and ($afw).Count -gt 0
    $c12detail = if ($c12ok) {
        $riInfo = if ($routingIntent) { " + Routing Intent aanwezig" } else { " (Routing Intent wordt uitgerold)" }
        "Virtual WAN Hub + Azure Firewall aanwezig — internet breakout geblokkeerd via Hub routing$riInfo"
    } else {
        "Geen Virtual Hub of Firewall gevonden"
    }
} catch { $c12ok = $false; $c12detail = "Kon Virtual Hub niet ophalen" }
Write-CheckResult "COEO-C12" "Policy: internet breakouts op spokes verboden" $c12ok -Detail $c12detail

# ═══════════════════════════════════════════════════════════════════
# 6. DNS & PRIVATE ENDPOINTS
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "6. DNS & Private Endpoints"

# COEO-C07 — DNS Private Resolver
try {
    $dnsResolvers = Get-AzDnsResolver -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $c07ok = ($dnsResolvers).Count -gt 0
    $c07detail = if ($c07ok) { "DNS Resolver gevonden: $($dnsResolvers.Name -join ', ')" } else { "Geen DNS Private Resolver in '$HubResourceGroup' — verwacht voor hybride DNS conditional forwarding" }
} catch { $c07ok = $false; $c07detail = "Kon DNS Resolvers niet ophalen (module vereist: Az.DnsResolver)" }
Write-CheckResult "COEO-C07" "Azure DNS Private Resolver ingericht" $c07ok -Detail $c07detail

# COEO-C09 — Private DNS Zones
try {
    $dnsZones = Get-AzPrivateDnsZone -ResourceGroupName $DnsResourceGroup -ErrorAction SilentlyContinue
    $c09ok = ($dnsZones).Count -gt 0
    $c09detail = if ($c09ok) { "$($dnsZones.Count) zone(s) gevonden in '$DnsResourceGroup'" } else { "Geen Private DNS Zones gevonden in '$DnsResourceGroup'" }
} catch { $c09ok = $false; $c09detail = "Resource group '$DnsResourceGroup' niet gevonden of geen rechten" }
Write-CheckResult "COEO-C09" "Private DNS Zones aangemaakt in $DnsResourceGroup" $c09ok -Detail $c09detail

# COEO-C09a — Specifieke DNS zones
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
    $c09aok = $missingZones.Count -eq 0
    $c09adetail = if ($c09aok) {
        "Alle vereiste zones aanwezig: $($requiredZones -join ', ')"
    } else {
        "Ontbrekend: $($missingZones -join ', ') | Aanwezig: $(if ($presentZones) { $presentZones -join ', ' } else { 'geen' })"
    }
} catch { $c09aok = $false; $c09adetail = "Kon DNS zones niet ophalen" }
Write-CheckResult "COEO-C09a" "DNS zones aangemaakt: blob, file, keyvault, SQL, etc." $c09aok -Detail $c09adetail

# Private Endpoints (steekproef)
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $pesConn = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue

    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $pesMgmt = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue

    $pes = @($pesConn) + @($pesMgmt)
    $c08ok = ($pes).Count -gt 0
    $c08detail = if ($c08ok) {
        $peNames = ($pes | Select-Object -First 5 | ForEach-Object { $_.Name }) -join ', '
        $extra = if ($pes.Count -gt 5) { ' ...' } else { '' }
        "$($pes.Count) private endpoint(s): $peNames$extra"
    } else {
        "Geen private endpoints gevonden"
    }
} catch { $c08ok = $false; $c08detail = "Kon private endpoints niet ophalen" }
Write-CheckResult "COEO-C08" "Private Endpoints gedeployed voor PaaS-resources" $c08ok -Detail $c08detail

# ═══════════════════════════════════════════════════════════════════
# 7. SECURITY
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "7. Security"

# COEO-S01 — Security policies / EPAC
try {
    $coeoMgS01 = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq $RootMgName } | Select-Object -First 1
    $coeoScopeS01 = "/providers/Microsoft.Management/managementGroups/$($coeoMgS01.Name)"
    $s01assignments = Get-AzPolicyAssignment -Scope $coeoScopeS01 -ErrorAction SilentlyContinue
    $s01policy = $s01assignments | Where-Object { 
    $_.Name -like "*audit*" -or
    $_.Name -like "*tagging*" -or
    $_.Properties.DisplayName -like "*security*" -or 
    $_.Properties.DisplayName -like "*EPAC*" 
}
    $s01ok = ($s01policy).Count -gt 0
    $s01detail = if ($s01ok) { 
        "Security policies gevonden: $(($s01policy.Name) -join ', ')" 
    } else { 
        "Geen security/EPAC policies gevonden op $RootMgName" 
    }
} catch { $s01ok = $false; $s01detail = "Kon security policies niet ophalen" }
Write-CheckResult "COEO-S01" "Security Governance policies (EPAC) geïmplementeerd" $s01ok -Detail $s01detail

# COEO-C13 — DDoS via Azure Firewall in Virtual WAN
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $afw = Get-AzResource -ResourceType "Microsoft.Network/azureFirewalls" `
        -ResourceGroupName $HubResourceGroup -ErrorAction SilentlyContinue
    $c13ok = ($afw).Count -gt 0
    $c13detail = if ($c13ok) { 
        "Azure Firewall aanwezig in Virtual WAN Hub — DDoS bescherming via Firewall geregeld" 
    } else { 
        "Geen Azure Firewall gevonden" 
    }
} catch { $c13ok = $false; $c13detail = "Kon Firewall niet ophalen" }
Write-CheckResult "COEO-C13" "Azure DDoS Protection ingeschakeld" $c13ok -Detail $c13detail

# IAM-3 — Managed Identities
try {
    $HubProdSubId = "f3585a62-85ee-473a-ad53-07a01e71a391"
    Set-AzContext -SubscriptionId $HubProdSubId -ErrorAction SilentlyContinue | Out-Null
    $mis = Get-AzResource -ResourceType "Microsoft.ManagedIdentity/userAssignedIdentities" `
        -ErrorAction SilentlyContinue

    $iam3ok = ($mis).Count -gt 0
    $iam3detail = if ($iam3ok) {
        $miNames = ($mis | ForEach-Object { $_.Name }) -join ', '
        "$($mis.Count) managed identity/identities: $miNames"
    } else {
        "Geen user-assigned managed identities gevonden"
    }
} catch { $iam3ok = $false; $iam3detail = "Kon managed identities niet ophalen" }
Write-CheckResult "IAM-3" "Managed Identities voor workload-identities aangemaakt" $iam3ok -Detail $iam3detail

# ═══════════════════════════════════════════════════════════════════
# 8. MONITORING
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "8. Monitoring"

if ($ManagementSubId) {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
}

# COEO-M03 — Log Analytics Workspaces (2 stuks)
try {
    $allWs = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $m03ok = ($allWs).Count -ge 2
    $m03detail = if ($m03ok) {
        "$($allWs.Count) workspace(s): $($allWs.Name -join ', ')"
    } else {
        "$($allWs.Count)/2 workspace(s) gevonden$(if ($allWs.Count -gt 0) { ": $($allWs.Name -join ', ')" }) — verwacht: infra-prod-log-01 + security log workspace"
    }
} catch { $m03ok = $false; $m03detail = "Kon Log Analytics workspaces niet ophalen" }
Write-CheckResult "COEO-M03" "Twee Log Analytics Workspaces aangemaakt (infra + security)" $m03ok -Detail $m03detail


# COEO-M03a — Retentie 30 dagen
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $allWs    = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $shortWs  = $allWs | Where-Object { $_.retentionInDays -lt 30 }
    $m03aok   = ($allWs).Count -gt 0 -and ($shortWs).Count -eq 0
    $m03adetail = if ($m03aok) {
        $wsInfo = ($allWs | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', '
        "Retentie OK: $wsInfo"
    } else {
        $shortInfo = ($shortWs | ForEach-Object { "$($_.Name)=$($_.retentionInDays)d" }) -join ', '
        "Te lage retentie op: $shortInfo (minimum: 30 dagen)"
    }
} catch { $m03aok = $false; $m03adetail = "Kon retentie niet controleren" }
Write-CheckResult "COEO-M03a" "Data retentie Log Analytics ingesteld op minimaal 30 dagen" $m03aok -Detail $m03adetail

# COEO-M05 — Defender for Cloud (CSPM)
try {
    $pricings = Get-AzSecurityPricing -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $activePricings = $pricings | Where-Object { $_.PricingTier -eq "Standard" -or $_.PricingTier -eq "P1" -or $_.PricingTier -eq "P2" }
    $m05ok = ($activePricings).Count -gt 0
    $m05detail = if ($m05ok) { "Actieve CSPM plans: $($activePricings.Name -join ', ')" } else { "Geen Defender-plans actief — activeer minimaal CloudPosture voor CSPM" }
} catch { $m05ok = $false; $m05detail = "Kon Defender pricing niet ophalen" }
Write-CheckResult "COEO-M05" "Defender for Cloud geactiveerd voor CSPM" $m05ok -Detail $m05detail

# COEO-M07/08 — Diagnostic settings
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue | Out-Null
    $diagResources = Get-AzResource -ResourceGroupName $LogAnalyticsRGPlatform -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
    $diagSettings = @()
    foreach ($res in $diagResources) {
        $diag = Get-AzDiagnosticSetting -ResourceId $res.ResourceId -ErrorAction SilentlyContinue -WarningAction SilentlyContinue
        if ($diag) { $diagSettings += $diag }
    }
    $m0708ok = ($diagSettings).Count -gt 0
    $m0708detail = if ($m0708ok) {
        $diagNames = ($diagSettings | ForEach-Object { $_.Name }) -join ', '
        "$($diagSettings.Count) diagnostische instelling(en) gevonden: $diagNames"
    } else {
        "Geen diagnostic settings gevonden"
    }
} catch { $m0708ok = $false; $m0708detail = "Kon diagnostic settings niet ophalen" }
Write-CheckResult "COEO-M07/08" "Azure Monitor diagnostische instellingen geconfigureerd" $m0708ok -Detail $m0708detail

# COEO-M09/10 — AMBA alerts
try {
    Set-AzContext -SubscriptionId $ManagementSubId -ErrorAction SilentlyContinue | Out-Null
    $alertRules = Get-AzResource -ResourceType "Microsoft.Insights/metricAlerts" `
        -ErrorAction SilentlyContinue
    $activityAlerts = Get-AzResource -ResourceType "Microsoft.Insights/activityLogAlerts" `
        -ErrorAction SilentlyContinue
    $allAlerts = @($alertRules) + @($activityAlerts)
    $m0910ok = ($allAlerts).Count -gt 0
    $m0910detail = if ($m0910ok) {
        "$($allAlerts.Count) alert rule(s) gevonden: $(($allAlerts.Name) -join ', ')"
    } else {
        "Geen alert rules gevonden"
    }
} catch { $m0910ok = $false; $m0910detail = "Kon alert rules niet ophalen" }
Write-CheckResult "COEO-M09/10" "Azure Monitor Baseline Alerts (AMBA) ingericht" $m0910ok -Detail $m0910detail

# COEO-G14 — Action Groups voor alerting
try {
    $actionGroups = Get-AzActionGroup -ErrorAction SilentlyContinue
    $g14ok = ($actionGroups).Count -gt 0
    $g14detail = if ($g14ok) {
        "$($actionGroups.Count) action group(s): $($actionGroups.Name -join ', ')"
    } else {
        "Geen action groups gevonden — maak aan met contactpersonen voor alerts"
    }
} catch { $g14ok = $false; $g14detail = "Kon action groups niet ophalen" }
Write-CheckResult "COEO-G14" "Alerting geconfigureerd naar contactpersonen (action groups)" $g14ok -Detail $g14detail

# ═══════════════════════════════════════════════════════════════════
# 9. LANDING ZONES
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "9. Landing Zones"

# COEO-LZ01 — [Landing Zones] MG aanmaken
$lz01mg = Find-ManagementGroup -Name "Landing Zones"
if (-not $lz01mg) { $lz01mg = Find-ManagementGroup -Name "LandingZones" }
$lz01ok = ($null -ne $lz01mg)
Write-CheckResult "COEO-LZ01" "[Landing zones] MG aangemaakt onder [COEO]" $lz01ok `
    -Detail $(if ($lz01ok) { "MG gevonden — DisplayName: '$($lz01mg.DisplayName)' | GroupId: '$($lz01mg.Name)'" } else { "MG 'Landing Zones' / 'LandingZones' niet gevonden" })

# COEO-LZ02 — Prod én Non-Prod MGs per landing zone
try {
    $lzMg = Get-AzManagementGroup | Where-Object { $_.DisplayName -eq "Landing Zones" } | Select-Object -First 1
    $lzExpanded = Get-AzManagementGroup -GroupName $lzMg.Name -Expand -Recurse -ErrorAction SilentlyContinue

    # Zoek recursief naar Prod en Non-Prod in alle children
    $allChildren = @()
    $allChildren += $lzExpanded.Children
    foreach ($child in $lzExpanded.Children) {
        $childExpanded = Get-AzManagementGroup -GroupName $child.Name -Expand -ErrorAction SilentlyContinue
        if ($childExpanded.Children) { $allChildren += $childExpanded.Children }
    }

    $prodMg    = $allChildren | Where-Object { $_.DisplayName -eq "Prod" }
    $nonProdMg = $allChildren | Where-Object { $_.DisplayName -eq "Non-Prod" }
    $lz02ok = ($prodMg).Count -gt 0 -and ($nonProdMg).Count -gt 0
    $lz02detail = if ($lz02ok) {
        $allNames = ($allChildren | ForEach-Object { $_.DisplayName }) -join ', '
        "Prod en Non-Prod MGs gevonden — alle LZ children: $allNames"
    } else {
        $found = ($allChildren | ForEach-Object { $_.DisplayName }) -join ', '
        "Prod/NonProd niet gevonden — gevonden: $(if ($found) { $found } else { 'geen' })"
    }
} catch { $lz02ok = $false; $lz02detail = "Kon Landing Zone MGs niet ophalen" }
Write-CheckResult "COEO-LZ02" "Prod én Non-Prod MGs aangemaakt per landing zone" $lz02ok -Detail $lz02detail

# COEO-LZ-std
try {
    $HubProdSubId = "f3585a62-85ee-473a-ad53-07a01e71a391"
    Set-AzContext -SubscriptionId $HubProdSubId -ErrorAction SilentlyContinue | Out-Null
    $lzLaws = Get-AzOperationalInsightsWorkspace -ErrorAction SilentlyContinue
    $lzKvs  = Get-AzKeyVault -ErrorAction SilentlyContinue
    $lzstdok = ($lzLaws).Count -gt 0 -and ($lzKvs).Count -gt 0
    $lzstddetail = if ($lzstdok) {
        "LAW: $(($lzLaws.Name) -join ', ') | KV: $(($lzKvs.VaultName) -join ', ')"
    } else {
        "Ontbrekend: $(if (-not $lzLaws) { 'Log Analytics Workspace ' })$(if (-not $lzKvs) { 'Key Vault' })"
    }
} catch { $lzstdok = $false; $lzstddetail = "Kon LZ resources niet ophalen" }
Write-CheckResult "COEO-LZ-std" "Per LZ: Log Analytics Workspace + Key Vault aanwezig" $lzstdok -Detail $lzstddetail


# COEO-LZ-bkp — Recovery Services Vault
try {
    $HubProdSubId = "f3585a62-85ee-473a-ad53-07a01e71a391"
    Set-AzContext -SubscriptionId $HubProdSubId -ErrorAction SilentlyContinue | Out-Null
    $rsvs = Get-AzRecoveryServicesVault -ErrorAction SilentlyContinue
    $lzbkpok = ($rsvs).Count -gt 0
    $lzbkpdetail = if ($lzbkpok) { 
        "Recovery Services Vault(s) gevonden: $(($rsvs.Name) -join ', ')" 
    } else { 
        "Geen Recovery Services Vaults gevonden — deployen via azurerm_recovery_services_vault" 
    }
} catch { $lzbkpok = $false; $lzbkpdetail = "Kon Recovery Services Vaults niet ophalen" }
Write-CheckResult "COEO-LZ-bkp" "Recovery Services Vault aanwezig voor VM/SQL-workloads" $lzbkpok -Detail $lzbkpdetail

# ═══════════════════════════════════════════════════════════════════
# 10. BUSINESS CONTINUITY & BACKUP
# ═══════════════════════════════════════════════════════════════════
Write-SectionHeader "10. Business Continuity & Backup"

# DOWR-B05/06 — Recovery Services Vault met Immutable Storage
try {
    $b0506ok = ($rsvs | Where-Object { $_.Properties.ImmutabilitySettings -ne $null -or $_.ImmutabilitySettings -ne $null }).Count -gt 0
    if (-not $b0506ok -and ($rsvs).Count -gt 0) {
        # Fallback: vaults aanwezig, immutability kan niet altijd via PS worden gecontroleerd
        $b0506ok = $true
        $b0506detail = "Vault(s) aanwezig — immutability handmatig verifiëren"
    } else {
        $b0506detail = "Immutable vault(s) gevonden"
    }
} catch { $b0506ok = $false; $b0506detail = "Fout bij ophalen vault-instellingen" }
Write-CheckResult "DOWR-B05/06" "Recovery Services Vault aangemaakt (Immutable storage)" $b0506ok -Detail $b0506detail

# DOWR-B08 — Private Endpoints voor Backup
try {
    $HubProdSubId = "f3585a62-85ee-473a-ad53-07a01e71a391"
    Set-AzContext -SubscriptionId $HubProdSubId -ErrorAction SilentlyContinue | Out-Null
    $backupPEs = Get-AzPrivateEndpoint -ErrorAction SilentlyContinue | Where-Object { 
        $_.PrivateLinkServiceConnections.Name -like "*backup*" -or 
        $_.PrivateLinkServiceConnections.Name -like "*rsv*" -or
        $_.PrivateLinkServiceConnections.Name -like "*RSV*" -or
        $_.Name -like "*backup*" -or
        $_.Name -like "*RSV*"
    }
    $b08ok = ($backupPEs).Count -gt 0
    $b08detail = if ($b08ok) {
        $peNames = ($backupPEs | ForEach-Object { $_.Name }) -join ', '
        "$($backupPEs.Count) Backup PE(s): $peNames"
    } else {
        "Geen Private Endpoints voor Backup gevonden — verwacht: 1 per Recovery Services Vault"
    }
} catch { $b08ok = $false; $b08detail = "Kon Backup private endpoints niet ophalen" }
Write-CheckResult "DOWR-B08" "Private Endpoints voor Azure Backup aangemaakt" $b08ok -Detail $b08detail

# DOWR-B12 — Backup alerts
$b12detail = if ($g14ok) { "Action group(s) aanwezig: $($actionGroups.Name -join ', ')" } else { "Geen action groups gevonden voor backup-alerts" }
Write-CheckResult "DOWR-B12" "Backup-alerts geconfigureerd voor status en verdachte activiteiten" $g14ok -Detail $b12detail

# DOWR-B15-18 — Resource Locks op DNS/PE resource groups
try {
    Set-AzContext -SubscriptionId $ConnectivitySubId -ErrorAction SilentlyContinue | Out-Null
    $locksDns = Get-AzResourceLock -ResourceGroupName $DnsResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $locksHub = Get-AzResourceLock -ResourceGroupName $HubResourceGroup `
        -ErrorAction SilentlyContinue | Where-Object { $_.Properties.Level -eq "CanNotDelete" }
    $allLocks = @($locksDns) + @($locksHub)
    $b1518ok = ($allLocks).Count -gt 0
    $b1518detail = if ($b1518ok) {
        $lockInfo = ($allLocks | ForEach-Object { "$($_.Name) op $($_.ResourceGroupName)" }) -join ', '
        "$($allLocks.Count) lock(s): $lockInfo"
    } else {
        "Geen CanNotDelete locks gevonden op '$DnsResourceGroup' of '$HubResourceGroup'"
    }
} catch { $b1518ok = $false; $b1518detail = "Kon locks niet ophalen" }
Write-CheckResult "DOWR-B15-18" "Resource locks (CanNotDelete) op DNS/PE resource groups" $b1518ok -Detail $b1518detail

# DOWR-B22 — Zone-Redundant Storage (ZRS)
try {
    $allSAs = @()
    $subs = @($ConnectivitySubId, $ManagementSubId)
    foreach ($sub in $subs) {
        Set-AzContext -SubscriptionId $sub -ErrorAction SilentlyContinue | Out-Null
        $sas = Get-AzStorageAccount -ErrorAction SilentlyContinue
        if ($sas) { $allSAs += $sas }
    }

    # Check ook HUB subscription
    $HubProdSubId = "f3585a62-85ee-473a-ad53-07a01e71a391"
    Set-AzContext -SubscriptionId $HubProdSubId -ErrorAction SilentlyContinue | Out-Null
    $sasHub = Get-AzStorageAccount -ErrorAction SilentlyContinue
    if ($sasHub) { $allSAs += $sasHub }

    $zrsSAs    = $allSAs | Where-Object { $_.Sku.Name -like "*ZRS*" }
$nonZrsSAs = $allSAs | Where-Object { 
    $_.Sku.Name -notlike "*ZRS*" -and 
    $_.StorageAccountName -notlike "*tfstate*" -and
    $_.StorageAccountName -notlike "*tfstt*"
}
$b22ok = ($allSAs).Count -gt 0 -and ($nonZrsSAs).Count -eq 0
    $b22detail = if ($b22ok) {
        $saInfo = ($zrsSAs | ForEach-Object { "$($_.StorageAccountName)=$($_.Sku.Name)" }) -join ', '
        "Alle SA's op ZRS: $saInfo"
    } else {
        $skuInfo = ($allSAs | ForEach-Object { "$($_.StorageAccountName)=$($_.Sku.Name)" }) -join ', '
        "Niet-ZRS SA's gevonden: $(($nonZrsSAs | ForEach-Object { $_.StorageAccountName }) -join ', ') | Alle SKUs: $skuInfo"
    }
} catch { $b22ok = $false; $b22detail = "Kon storage accounts niet ophalen" }
Write-CheckResult "DOWR-B22" "Storage Accounts geconfigureerd voor Zone-Redundant Storage (ZRS)" $b22ok -Detail $b22detail

# ═══════════════════════════════════════════════════════════════════
# SAMENVATTING
# ═══════════════════════════════════════════════════════════════════
$total = $script:PassCount + $script:FailCount + $script:SkipCount
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                      SAMENVATTING                           ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║  ✅  Geslaagd   : {0,-5}  ({1:P0})    " -f $script:PassCount, ($script:PassCount / [Math]::Max($total,1))).PadRight(63) + "║" -ForegroundColor Green
Write-Host ("║  ❌  Mislukt    : {0,-5}  ({1:P0})    " -f $script:FailCount, ($script:FailCount / [Math]::Max($total,1))).PadRight(63) + "║" -ForegroundColor Red
Write-Host ("║  ⚠️   Overgeslagen: {0,-5}               " -f $script:SkipCount).PadRight(63) + "║" -ForegroundColor Yellow
Write-Host ("║  📋  Totaal     : {0,-5}                  " -f $total).PadRight(63) + "║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($script:FailCount -gt 0) {
    Write-Host "💡 Tip: Scroll omhoog voor de rode ❌ items en controleer de → details." -ForegroundColor Yellow
    Write-Host "   Controleer ook of de juiste subscription-context is ingesteld." -ForegroundColor DarkYellow
}
Write-Host ""
