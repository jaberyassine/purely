function Select-PrometheusApiService {
    param([object[]]$Services)
    # Operator-generated/headless Services and client-facing Services can both
    # expose 9090. Labels also vary across operator/chart versions.
    $candidates = @($Services | Where-Object {
        $_.spec.type -eq 'ClusterIP' -and $_.spec.clusterIP -ne 'None' -and
        @($_.spec.ports | Where-Object { $_.port -eq 9090 }).Count -gt 0
    })
    if ($candidates.Count -ne 1) {
        $Services | Select-Object @{Name='Name';Expression={$_.metadata.name}},@{Name='Type';Expression={$_.spec.type}},@{Name='ClusterIP';Expression={$_.spec.clusterIP}},@{Name='Ports';Expression={$_.spec.ports.port -join ','}} | Format-Table -AutoSize | Out-Host
        throw 'Expected one non-headless ClusterIP Service exposing the Prometheus API on port 9090.'
    }
    return $candidates[0]
}
