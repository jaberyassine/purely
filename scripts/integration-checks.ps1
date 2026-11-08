# Loaded by Test-Runtime.ps1 only when -IncludeIntegration is requested.
function New-FixtureSecret {
    param([int]$Length = 32)
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return [Convert]::ToBase64String($bytes)
}
function Invoke-FixtureApi {
    param([string]$Name,[string]$Path,[string]$Method='GET',
        [object]$Body=$null,[string]$Token='', [int]$ExpectedStatus=200)
    $responsePath = Join-Path $runDirectory ($Name + '.json')
    $arguments = @('--silent','--show-error','--max-time','30','--cacert',$certificate,
        '--header','Accept: application/json','--request',$Method,
        '--output',$responsePath,'--write-out','%{http_code}')
    $temporaryFiles = [System.Collections.Generic.List[string]]::new()
    try {
        if ($null -ne $Body) {
            $requestPath = Join-Path $runDirectory ($Name + '-request.json')
            $temporaryFiles.Add($requestPath)
            [IO.File]::WriteAllText($requestPath,($Body | ConvertTo-Json -Depth 12),[Text.Encoding]::ASCII)
            $arguments += @('--header','Content-Type: application/json','--data-binary',('@' + $requestPath))
        }
        if ($Token) {
            # Keep bearer tokens out of process command-line arguments.
            $headerPath = Join-Path $runDirectory ($Name + '-authorization.txt')
            $temporaryFiles.Add($headerPath)
            [IO.File]::WriteAllText($headerPath,('Authorization: Bearer ' + $Token),[Text.Encoding]::ASCII)
            $arguments += @('--header',('@' + $headerPath))
        }
        $status = (Invoke-Native $curl ($arguments + @($frontendUri + $Path)) | Out-String).Trim()
        if ($status -ne [string]$ExpectedStatus) { throw "$Name returned HTTP $status; expected $ExpectedStatus. See $responsePath and container logs." }
        try { $response = Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json }
        catch {
            $failure = [Exception]::new("$Name returned invalid JSON. See $responsePath.")
            $failure.Data['NonRetryable'] = $true
            throw $failure
        }
        # Lombok's isSuccess() getter is serialized as the JSON field 'success'.
        if ($ExpectedStatus -ge 200 -and $ExpectedStatus -lt 300 -and
            ($response.success -isnot [bool] -or $response.success -ne $true)) {
            $failure = [Exception]::new("$Name did not return boolean success=true. See $responsePath.")
            $failure.Data['NonRetryable'] = $true
            throw $failure
        }
        return $response
    } finally {
        foreach ($file in $temporaryFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
        # Sign-in responses contain a temporary JWT; retain no token in the report.
        if ($Name -like '*signin*') { Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue }
    }
}
function Wait-FixtureRead {
    param([string]$Name,[string]$Path,[string]$Token='')
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $lastNotice = 0
    while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        try { return (Invoke-FixtureApi $Name $Path -Token $Token) }
        catch {
            if ($_.Exception.Data['NonRetryable'] -or $_.Exception.Data['NativeExitCode'] -eq 60) { throw }
            $lastFailure = $_.Exception.Message
        }
        if (($clock.Elapsed.TotalSeconds - $lastNotice) -ge 15) {
            Write-Host "[WAIT] $Name discovery: $([int]$clock.Elapsed.TotalSeconds)s"
            $lastNotice = $clock.Elapsed.TotalSeconds
        }
        Start-Sleep -Seconds 2
    }
    throw "$Name discovery/read timed out. $lastFailure"
}
function Test-BusinessIntegration {
    $secretFiles = [System.Collections.Generic.List[string]]::new()
    try {
        # Local test dependency only; never connect to Atlas or a production URI.
        $mongoImage = 'purely-local/mongo-integration:validation'
        $mongoContext = Join-Path $projectRoot 'scripts\test-mongo'
        Write-Host '[PREPARE] Building the minimal MongoDB test image; build output is in commands.log.'
        Invoke-Native $docker @('build','--pull','--no-cache','--tag',$mongoImage,$mongoContext) | Out-Null
        Write-Host '[SCAN] Temporary MongoDB image; HIGH/CRITICAL findings still block execution.'
        $mongoImageId = (Invoke-Native $docker @('image','inspect','--format','{{.Id}}',$mongoImage) | Out-String).Trim()
        if ($mongoImageId -notmatch '^sha256:[a-f0-9]{64}$') { throw 'Invalid MongoDB image ID.' }
        $scanInput = Join-Path $runDirectory 'mongo-scan-input'
        $scanReports = Join-Path $runDirectory 'mongo-scan-reports'
        $scanCache = Join-Path $projectRoot '.validation\trivy\cache'
        New-Item -ItemType Directory -Path $scanInput,$scanReports,$scanCache -Force | Out-Null
        $mongoArchive = Join-Path $scanInput 'mongo.tar'
        try {
            Invoke-Native $docker @('image','save','--output',$mongoArchive,$mongoImageId) | Out-Null
            Invoke-Native $docker @('pull','aquasec/trivy:0.76.2') | Out-Null
            Invoke-Native $docker @('run','--rm',
                '--mount',"type=bind,source=$scanInput,target=/input,readonly",
                '--mount',"type=bind,source=$scanReports,target=/reports",
                '--mount',"type=bind,source=$scanCache,target=/root/.cache",
                'aquasec/trivy:0.76.2','image','--input','/input/mongo.tar',
                '--scanners','vuln,secret','--severity','HIGH,CRITICAL','--format','json',
                '--output','/reports/mongo.json','--timeout','15m','--exit-code','0') | Out-Null
        } finally { Remove-Item -LiteralPath $mongoArchive -Force -ErrorAction SilentlyContinue }
        $report = Get-Content (Join-Path $scanReports 'mongo.json') -Raw | ConvertFrom-Json
        if ($report.SchemaVersion -ne 2 -or -not $report.ArtifactName -or -not $report.PSObject.Properties['Results']) { throw 'Invalid database scan report.' }
        $findings = @($report.Results | ForEach-Object { $_.Vulnerabilities; $_.Secrets } | Where-Object { $_.Severity -in @('HIGH','CRITICAL') })
        if ($findings.Count) { throw "Temporary MongoDB image blocked: $($findings.Count) HIGH/CRITICAL findings. Review $scanReports; do not bypass this gate." }
        Add-Result 'integration-mongo-scan' 'PASS' $mongoImageId

        $rootPassword = [Guid]::NewGuid().ToString('N')
        $databasePassword = [Guid]::NewGuid().ToString('N')
        $mongoEnv = Join-Path $runDirectory 'mongo-test.env'
        $secretFiles.Add($mongoEnv)
        [IO.File]::WriteAllLines($mongoEnv,@("FIXTURE_ROOT_PASSWORD=$rootPassword","FIXTURE_DB_PASSWORD=$databasePassword"),[Text.Encoding]::ASCII)
        $seedPath = Join-Path $runDirectory 'mongo-fixture.js'
        $seedText = @'
const admin = db.getSiblingDB('admin');
admin.createUser({user:'fixture_root', pwd:process.env.FIXTURE_ROOT_PASSWORD, roles:['root']});
if (!admin.auth('fixture_root', process.env.FIXTURE_ROOT_PASSWORD)) throw new Error('Fixture admin authentication failed');
for (const [user, database, role] of [
  ['auth-service','fixture_identity','readWrite'], ['user-service','fixture_identity','read'],
  ['product-service','fixture_product','readWrite'], ['category-service','fixture_category','readWrite'],
  ['cart-service','fixture_cart','readWrite'], ['order-service','fixture_order','readWrite']
]) {
  db.getSiblingDB(database).createUser({user, pwd:process.env.FIXTURE_DB_PASSWORD, roles:[{role,db:database}]});
}
db.getSiblingDB('fixture_category').categories.insertOne({_id:ObjectId('000000000000000000000001'),categoryName:'Local fixture',description:'Disposable integration fixture',imageUrl:'fixture.png'});
db.getSiblingDB('fixture_product').products.insertOne({_id:ObjectId('000000000000000000000002'),productName:'Fixture product',price:25,description:'Disposable integration fixture',imageUrl:'fixture.png',categoryId:'000000000000000000000001',categoryName:'Local fixture'});
print('Fixture databases initialized');
'@
        [IO.File]::WriteAllText($seedPath,$seedText,[Text.Encoding]::ASCII)
        $mongoArguments = @('create','--name',('purely-mongo-' + $runId),'--network',$ownedNetwork,
            '--network-alias','purely-test-mongo','--pull','never','--user','999:999','--read-only',
            '--cap-drop','ALL','--security-opt','no-new-privileges','--memory','768m','--cpus','1',
            '--tmpfs','/data/db:rw,nosuid,size=384m,uid=999,gid=999',
            '--tmpfs','/data/configdb:rw,nosuid,size=8m,uid=999,gid=999',
            '--tmpfs','/tmp:rw,nosuid,size=32m,uid=999,gid=999','--env-file',$mongoEnv,
            '--mount',"type=bind,source=$seedPath,target=/fixture.js,readonly",
            '--entrypoint','mongod',$mongoImageId,'--auth','--bind_ip_all','--wiredTigerCacheSizeGB','0.25')
        $mongo = (Invoke-Native $docker $mongoArguments | Out-String).Trim()
        if ($mongo -notmatch '^[a-f0-9]{64}$') { throw 'Invalid MongoDB container ID.' }
        $ownedContainers.Add($mongo)
        Invoke-Native $docker @('start',$mongo) | Out-Null
        $clock = [Diagnostics.Stopwatch]::StartNew()
        $mongoReady = $false
        while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            try {
                Invoke-Native $docker @('exec',$mongo,'mongosh','--quiet','--eval','quit(db.adminCommand({ping:1}).ok === 1 ? 0 : 1)') | Out-Null
                $mongoReady = $true; break
            } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $mongoReady) { throw 'Temporary MongoDB did not start.' }
        Invoke-Native $docker @('exec',$mongo,'mongosh','--quiet','--file','/fixture.js') | Out-Null
        Add-Result 'integration-mongo-fixture' 'PASS' 'Authenticated temporary databases; no published MongoDB port; data on tmpfs'

        $jwtSecret = New-FixtureSecret
        $services = @(
            @{Name='auth-service';Port=9031;Database='fixture_identity'},
            @{Name='user-service';Port=9052;Database='fixture_identity'},
            @{Name='category-service';Port=9001;Database='fixture_category'},
            @{Name='product-service';Port=9013;Database='fixture_product'},
            @{Name='cart-service';Port=9061;Database='fixture_cart'},
            @{Name='order-service';Port=9071;Database='fixture_order'}
        )
        $startedServices = @()
        foreach ($service in $services) {
            $name = $service.Name
            $envFile = Join-Path $runDirectory ($name + '-test.env')
            $secretFiles.Add($envFile)
            $values = @("MONGODB_URI=mongodb://${name}:${databasePassword}@purely-test-mongo:27017/$($service.Database)?authSource=$($service.Database)")
            if ($name -eq 'auth-service') { $values += "JWT_SECRET=$jwtSecret" }
            [IO.File]::WriteAllLines($envFile,$values,[Text.Encoding]::ASCII)
            $id = Start-OwnedContainer ('purely-' + $name + '-' + $runId) ("purely-local/${name}:validation") (
                $javaOptions + @('--network-alias',$name,'--env-file',$envFile,'--publish',("127.0.0.1::$($service.Port)")))
            $startedServices += @{Name=$name;Uri=(Get-PublishedUri $id $service.Port)}
        }
        foreach ($service in $startedServices) { Wait-Healthy $service.Name $service.Uri }

        $catalog = Wait-FixtureRead 'integration-product-route' '/product-service/product/get/all'
        if (@($catalog.response).Count -ne 1 -or $catalog.response[0].id -ne '000000000000000000000002' -or $catalog.response[0].price -ne 25) { throw 'Product fixture response does not match seeded data.' }
        $categories = Wait-FixtureRead 'integration-category-route' '/category-service/category/get/all'
        if (@($categories.response).Count -ne 1 -or $categories.response[0].id -ne '000000000000000000000001') { throw 'Category fixture does not match seeded data.' }
        $categoryProducts = Wait-FixtureRead 'integration-product-category' '/product-service/product/get/byCategory?id=000000000000000000000001'
        if (@($categoryProducts.response).Count -ne 1) { throw 'Product-to-category lookup failed.' }
        Add-Result 'integration-catalog' 'PASS' 'Real MongoDB product/category reads via HTTPS, gateway and service discovery'

        # A read-only invalid-token request waits for auth discovery before writes.
        # Its HTTP 401 is expected, so poll explicitly without retrying registration.
        $clock = [Diagnostics.Stopwatch]::StartNew(); $authReady = $false
        while ($clock.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
            try {
                [void](Invoke-FixtureApi 'integration-auth-route' '/auth-service/auth/isValidToken?token=invalid' -ExpectedStatus 401)
                $authReady = $true; break
            } catch { Start-Sleep -Seconds 2 }
        }
        if (-not $authReady) { throw 'Auth route did not become available.' }
        $password = 'T!' + [Guid]::NewGuid().ToString('N').Substring(0,16)
        $email = 'fixture-' + $runId + '@example.invalid'
        [void](Invoke-FixtureApi 'integration-signup' '/auth-service/auth/signup' 'POST' @{
            userName=('test' + $runId);email=$email;password=$password;roles=@('admin')
        } -ExpectedStatus 201)
        $signin = Invoke-FixtureApi 'integration-signin' '/auth-service/auth/signin' 'POST' @{email=$email;password=$password}
        $token = [string]$signin.response.token
        $userId = [string]$signin.response.id
        if (-not $token -or -not $userId -or @($signin.response.roles).Count -ne 1 -or $signin.response.roles[0] -ne 'ROLE_USER') {
            throw 'Sign-in identity/roles failed: public registration must only grant ROLE_USER, even when admin is requested.'
        }
        Add-Result 'integration-authentication' 'PASS' 'Public signup, real password authentication and JWT; admin role request cannot elevate privileges'
        [void](Invoke-FixtureApi 'integration-bad-signin' '/auth-service/auth/signin' 'POST' @{email=$email;password='incorrect-password'} -ExpectedStatus 401)
        $user = Wait-FixtureRead 'integration-user' ("/user-service/user/get/byId?id=$userId")
        if ($user.response.userId -ne $userId) { throw 'User service cannot read the newly registered identity.' }
        $cart = Wait-FixtureRead 'integration-empty-cart' '/cart-service/cart/get/byUser' -Token $token
        if ($cart.response.noOfCartItems -ne 0) { throw 'New fixture cart was not empty.' }
        [void](Invoke-FixtureApi 'integration-anonymous-cart' '/cart-service/cart/get/byUser' -ExpectedStatus 401)
        [void](Invoke-FixtureApi 'integration-user-admin-denied' '/category-service/admin/category/create' 'POST' @{
            name='Must not be created';description='Unauthorized fixture';imageUrl='fixture.png'
        } -Token $token -ExpectedStatus 403)
        Add-Result 'integration-access-control' 'PASS' 'Wrong password and anonymous cart rejected; ordinary user denied admin category write'

        [void](Invoke-FixtureApi 'integration-cart-add' '/cart-service/cart/add' 'POST' @{productId='000000000000000000000002';quantity=1} -Token $token)
        $cart = Invoke-FixtureApi 'integration-cart-read' '/cart-service/cart/get/byUser' -Token $token
        if ($cart.response.noOfCartItems -ne 1 -or $cart.response.subtotal -ne 25 -or @($cart.response.cartItems).Count -ne 1) { throw 'Cart quantity/subtotal mismatch.' }
        Add-Result 'integration-cart' 'PASS' 'Product added and persisted; cart quantity=1 and subtotal=25'

        $secondEmail = 'other-' + $runId + '@example.invalid'
        [void](Invoke-FixtureApi 'integration-other-signup' '/auth-service/auth/signup' 'POST' @{
            userName=('other' + $runId);email=$secondEmail;password=$password
        } -ExpectedStatus 201)
        $secondSignin = Invoke-FixtureApi 'integration-other-signin' '/auth-service/auth/signin' 'POST' @{email=$secondEmail;password=$password}
        $otherToken = [string]$secondSignin.response.token
        if (-not $otherToken) { throw 'Second user sign-in failed.' }
        [void](Invoke-FixtureApi 'integration-foreign-cart-read' ("/cart-service/cart/get/byId?id=$($cart.response.cartId)") -Token $otherToken -ExpectedStatus 404)
        [void](Invoke-FixtureApi 'integration-foreign-cart-clear' ("/cart-service/cart/clear/byId?id=$($cart.response.cartId)") 'DELETE' -Token $otherToken -ExpectedStatus 404)

        $initialOrders = Wait-FixtureRead 'integration-order-route' '/order-service/order/get/byUser' -Token $token
        if (@($initialOrders.response).Count -ne 0) { throw 'New fixture account already has orders.' }
        [void](Invoke-FixtureApi 'integration-order-create' '/order-service/order/create' 'POST' @{
            cartId=$cart.response.cartId;firstName='Local';lastName='Fixture';addressLine1='Test address';addressLine2='';city='Test';phoneNo='0000000000'
        } -Token $token)
        $orders = Invoke-FixtureApi 'integration-orders-read' '/order-service/order/get/byUser' -Token $token
        if (@($orders.response).Count -ne 1 -or $orders.response[0].orderAmt -ne 25 -or $orders.response[0].userId -ne $userId -or $orders.response[0].orderStatus -ne 'PENDING') { throw 'Persisted order does not match the cart.' }
        $cleared = Invoke-FixtureApi 'integration-cart-after-order' '/cart-service/cart/get/byUser' -Token $token
        if ($cleared.response.noOfCartItems -ne 0 -or $cleared.response.subtotal -ne 0) { throw 'Cart was not cleared after checkout.' }
        Add-Result 'integration-order' 'PASS' 'Order persisted with amount=25 and PENDING; cart cleared after successful checkout'
        $orderId = $orders.response[0].id
        [void](Invoke-FixtureApi 'integration-foreign-order-cancel' ("/order-service/order/cancel?orderId=$orderId") 'PATCH' -Token $otherToken -ExpectedStatus 404)
        [void](Invoke-FixtureApi 'integration-owner-order-cancel' ("/order-service/order/cancel?orderId=$orderId") 'PATCH' -Token $token)
        $cancelled = Invoke-FixtureApi 'integration-cancelled-order' '/order-service/order/get/byUser' -Token $token
        if ($cancelled.response[0].orderStatus -ne 'CANCELLED') { throw 'Owner cancellation was not persisted.' }
        Add-Result 'integration-ownership' 'PASS' 'Second user denied cart read/clear and order cancellation; owner cancellation succeeds'
    } finally {
        foreach ($file in $secretFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    }
}
