using System.Diagnostics;
using System.Globalization;
using System.Text;
using FrameMind.Application.Common;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace FrameMind.Infrastructure.Media;

public sealed record ProcessResult(int ExitCode, string StdOut, string StdErr);

/// <summary>Runs external tools with argument lists (never through a shell).</summary>
public sealed class ProcessRunner(ILogger<ProcessRunner> logger)
{
    public async Task<ProcessResult> RunAsync(
        string fileName, IEnumerable<string> args, TimeSpan timeout, CancellationToken ct,
        string? workingDirectory = null, bool throwOnError = true)
    {
        var psi = new ProcessStartInfo(fileName)
        {
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
            WorkingDirectory = workingDirectory ?? Environment.CurrentDirectory,
        };
        foreach (var arg in args) psi.ArgumentList.Add(arg);

        using var process = new Process { StartInfo = psi };
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        process.OutputDataReceived += (_, e) => { if (e.Data is not null) stdout.AppendLine(e.Data); };
        process.ErrorDataReceived += (_, e) => { if (e.Data is not null) stderr.AppendLine(e.Data); };

        try { process.Start(); }
        catch (Exception ex) { throw new ExternalServiceException($"'{fileName}' is not installed or not on PATH.", ex); }

        process.BeginOutputReadLine();
        process.BeginErrorReadLine();

        using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
        timeoutCts.CancelAfter(timeout);
        try
        {
            await process.WaitForExitAsync(timeoutCts.Token);
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { /* already exited */ }
            ct.ThrowIfCancellationRequested();
            throw new ExternalServiceException($"'{Path.GetFileName(fileName)}' timed out after {timeout.TotalSeconds:0}s.");
        }

        process.WaitForExit(); // flush async output handlers
        var result = new ProcessResult(process.ExitCode, stdout.ToString(), stderr.ToString());
        if (throwOnError && result.ExitCode != 0)
        {
            var tail = result.StdErr.Length > 2000 ? result.StdErr[^2000..] : result.StdErr;
            logger.LogWarning("{Tool} exited with {Code}: {StdErr}", fileName, result.ExitCode, tail);
            throw new ExternalServiceException($"'{Path.GetFileName(fileName)}' failed (exit code {result.ExitCode}).");
        }
        return result;
    }
}

public sealed class FfmpegTools(ProcessRunner runner, IOptions<MediaOptions> options)
{
    private readonly MediaOptions _opt = options.Value;

    public Task<ProcessResult> FfmpegAsync(IEnumerable<string> args, CancellationToken ct, string? workDir = null, TimeSpan? timeout = null) =>
        runner.RunAsync(_opt.FfmpegPath, ["-hide_banner", "-loglevel", "error", "-y", .. args], timeout ?? TimeSpan.FromMinutes(10), ct, workDir);

    public async Task<double> DurationAsync(string path, CancellationToken ct)
    {
        var result = await runner.RunAsync(_opt.FfprobePath,
            ["-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", path],
            TimeSpan.FromSeconds(30), ct);
        return double.TryParse(result.StdOut.Trim(), NumberStyles.Float, CultureInfo.InvariantCulture, out var seconds)
            ? seconds : 0;
    }
}
