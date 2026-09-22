$ErrorActionPreference = 'Stop'
$outDir = 'D:\smart-medicine-box\dist\软著申请材料_最终版'
$jobs = @(
    @{ Name = '智能药箱家庭用药管理系统_操作手册.docx'; Toc = $true },
    @{ Name = '智能药箱家庭用药管理系统_软件代码.docx'; Toc = $false },
    @{ Name = '智能药箱家庭用药管理系统_申请信息确认表.docx'; Toc = $false }
)
foreach ($job in $jobs) {
    $path = Join-Path $outDir $job.Name
    $word = $null
    $doc = $null
    try {
        $word = New-Object -ComObject Word.Application
        $word.Visible = $false
        $word.DisplayAlerts = 0
        $doc = $word.Documents.Open($path, $false, $false)
        $doc.Repaginate()
        if ($job.Toc) {
            foreach ($toc in $doc.TablesOfContents) { $toc.Update() }
        }
        $doc.Fields.Update() | Out-Null
        foreach ($section in $doc.Sections) {
            foreach ($header in $section.Headers) { if ($header.Range.Fields.Count -gt 0) { $header.Range.Fields.Update() | Out-Null } }
            foreach ($footer in $section.Footers) { if ($footer.Range.Fields.Count -gt 0) { $footer.Range.Fields.Update() | Out-Null } }
        }
        $doc.Repaginate()
        $doc.Save()
        $pdf = [System.IO.Path]::ChangeExtension($path, '.pdf')
        $doc.ExportAsFixedFormat($pdf, 17)
        Write-Output "$($job.Name) -> $pdf"
    }
    catch {
        Write-Warning "$($job.Name): $($_.Exception.Message)"
    }
    finally {
        if ($doc -ne $null) { try { $doc.Close(0) } catch {} }
        if ($word -ne $null) { try { $word.Quit() } catch {}; try { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($word) | Out-Null } catch {} }
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
    }
}

