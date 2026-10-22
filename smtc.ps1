# JellyVault's VCR in Windows' own media controls (the System Media Transport Controls: the media keys, whatever has
# the focus, and the player in the volume flyout), as mpris.py is on Linux; mpris.gd starts it, and talks to it the same.
#
# stdin, a line of JSON at a time from the game: {"status", "id", "title", "album", "length", "pos", "art"} (seconds).
# stdout, a line a press: playpause, play, pause, stop, next, prev, pos <s>.
# It goes when stdin does (the game's gone).

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null = [Windows.Media.Playback.MediaPlayer, Windows.Media, ContentType = WindowsRuntime]
$null = [Windows.Storage.Streams.RandomAccessStreamReference, Windows.Storage.Streams, ContentType = WindowsRuntime]

$player = New-Object Windows.Media.Playback.MediaPlayer  # (only for its controls: it never plays anything)
$player.CommandManager.IsEnabled = $false
$smtc = $player.SystemMediaTransportControls
$smtc.IsEnabled = $true
$smtc.IsPlayEnabled = $true
$smtc.IsPauseEnabled = $true
$smtc.IsStopEnabled = $true
$smtc.IsNextEnabled = $true
$smtc.IsPreviousEnabled = $true

# (PowerShell can't take Windows RT events itself: a few lines of C# take them, and queue a line a press)
$refs = @("Windows.Foundation", "Windows.Media") | ForEach-Object { "$env:windir\System32\WinMetadata\$_.winmd" }
$refs += @("System.Runtime", "System.Runtime.WindowsRuntime", "System.Runtime.InteropServices.WindowsRuntime") | ForEach-Object {
	$name = $_
	$found = foreach ($key in "b03f5f7f11d50a3a", "b77a5c561934e089") {  # (the framework's two keys: the facades are signed with the one)
		try { [Reflection.Assembly]::Load("$name, Version=4.0.0.0, Culture=neutral, PublicKeyToken=$key").Location; break } catch {}
	}
	$found
}
$cs = New-Object CodeDom.Compiler.CompilerParameters  # (the compiler itself, not Add-Type: that tries to load the .winmds, and can't)
$cs.GenerateInMemory = $true
$cs.ReferencedAssemblies.AddRange([string[]]$refs)
$built = (New-Object Microsoft.CSharp.CSharpCodeProvider).CompileAssemblyFromSource($cs, @"
using System.Collections.Concurrent;
using System.Globalization;
using Windows.Media;
public static class Presses {
	public static ConcurrentQueue<string> Q = new ConcurrentQueue<string>();
	public static void Hook(SystemMediaTransportControls s) {
		s.ButtonPressed += (o, e) => {
			switch (e.Button) {
				case SystemMediaTransportControlsButton.Play: Q.Enqueue("play"); break;
				case SystemMediaTransportControlsButton.Pause: Q.Enqueue("pause"); break;
				case SystemMediaTransportControlsButton.Stop: Q.Enqueue("stop"); break;
				case SystemMediaTransportControlsButton.Next: Q.Enqueue("next"); break;
				case SystemMediaTransportControlsButton.Previous: Q.Enqueue("prev"); break;
			}
		};
		s.PlaybackPositionChangeRequested += (o, e) => Q.Enqueue("pos " + e.RequestedPlaybackPosition.TotalSeconds.ToString(CultureInfo.InvariantCulture));
	}
}
"@)
if ($built.Errors.HasErrors) { throw ($built.Errors | Out-String) }
$Presses = $built.CompiledAssembly.GetType("Presses")
$Presses::Hook($smtc)
$Q = $Presses::Q

$out = [Console]::Out
$in = [Console]::In
$read = $in.ReadLineAsync()
$shown = ""  # (the title and art last put up: only redone when they change)

function Show($s) {
	$status = switch ($s.status) { "Playing" { "Playing" } "Paused" { "Paused" } default { "Stopped" } }
	$smtc.PlaybackStatus = [Windows.Media.MediaPlaybackStatus]::$status
	$key = "$($s.id)|$($s.art)"
	if ($status -ne "Stopped" -and $key -ne $script:shown) {
		$script:shown = $key
		$d = $smtc.DisplayUpdater
		$d.ClearAll()
		$d.Type = [Windows.Media.MediaPlaybackType]::Video
		$d.VideoProperties.Title = [string]$s.title
		$d.VideoProperties.Subtitle = [string]$s.album
		if ($s.art) {
			try { $d.Thumbnail = [Windows.Storage.Streams.RandomAccessStreamReference]::CreateFromUri([Uri]::new(($s.art -replace "^file://", ""))) } catch {}  # (a path to a proper file:/// one)
		}
		$d.Update()
	}
	if ($s.length -gt 0) {
		$t = New-Object Windows.Media.SystemMediaTransportControlsTimelineProperties
		$t.StartTime = [TimeSpan]::Zero
		$t.MinSeekTime = [TimeSpan]::Zero
		$t.EndTime = [TimeSpan]::FromSeconds($s.length)
		$t.MaxSeekTime = $t.EndTime
		$t.Position = [TimeSpan]::FromSeconds([Math]::Min($s.pos, $s.length))
		$smtc.UpdateTimelineProperties($t)
	}
}

while ($true) {
	if ($read.IsCompleted) {
		$line = $read.Result
		if ($null -eq $line) { break }  # (the game's gone)
		try { Show (ConvertFrom-Json $line) } catch { [Console]::Error.WriteLine("smtc: $_") }
		$read = $in.ReadLineAsync()
	}
	$press = $null
	while ($Q.TryDequeue([ref]$press)) {
		$out.WriteLine($press)
		$out.Flush()
	}
	Start-Sleep -Milliseconds 50
}
