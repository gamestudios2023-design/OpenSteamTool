using System.IO;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using CloudRedirect.Resources;

namespace CloudRedirect.Pages;

public partial class CloudProviderPage : Page
{
    private Services.OAuthService? _oauth;
    private CancellationTokenSource? _authCts;
    private bool _isAuthenticating;
    private bool _loading;
    private readonly StringBuilder _logBuffer = new();

    // Upload in-flight cap (MB). Only shown/saved for Google Drive.
    private const int InFlightDefaultMb = 24;
    private const int InFlightMinMb = 24;
    private const int InFlightMaxMb = 64;
    // Suppresses the slider ValueChanged handler during programmatic load.
    private bool _inFlightLoading;

    public CloudProviderPage()
    {
        InitializeComponent();
        Loaded += async (_, _) =>
        {
            try { await LoadCurrentConfigAsync(); }
            catch { }
        };
        // Cancel in-flight OAuth on Unloaded to stop the loopback listener and prevent leaked references.
        Unloaded += (_, _) =>
        {
            if (_isAuthenticating)
                _authCts?.Cancel();
        };
    }

    /// <summary>Off-thread config snapshot for LoadCurrentConfigAsync.</summary>
    private sealed record LoadedConfigSnapshot(
        Services.CloudConfig? Config,
        string DefaultLocalPath,
        string PathTextOverride,
        Services.TokenStatus? TokenStatus,
        int UploadInFlightMb);

    // M14: Read config + token status off UI thread to avoid disk/DPAPI stall.
    private async Task LoadCurrentConfigAsync()
    {
        // Set _loading before I/O to suppress SelectionChanged during init.
        _loading = true;
        try
        {
            var snapshot = await Task.Run(() =>
            {
                var config = Services.SteamDetector.ReadConfig();
                var steamPath = Services.SteamDetector.FindSteamPath();
                var defaultLocal = steamPath != null
                    ? Path.Combine(steamPath, "localcloud")
                    : "";

                string pathOverride = "";
                if (config != null)
                {
                    if (config.TokenPath != null)
                        pathOverride = config.TokenPath;
                    else if (config.SyncPath != null)
                        pathOverride = config.SyncPath;
                }

                Services.TokenStatus? tokenStatus = null;
                if (config?.TokenPath != null)
                    tokenStatus = Services.OAuthService.CheckTokenStatus(config.TokenPath);

                return new LoadedConfigSnapshot(config, defaultLocal, pathOverride, tokenStatus, ReadUploadInFlightMb());
            });

            ApplyLoadedSnapshot(snapshot);
        }
        catch (Exception ex)
        {
            AuthStatus.Text = S.Format("CloudProvider_ErrorReadingConfig", ex.Message);
        }
        finally
        {
            _loading = false;
        }
    }

    private void ApplyLoadedSnapshot(LoadedConfigSnapshot snap)
    {
        ApplyUploadInFlight(snap.UploadInFlightMb);

        if (snap.Config == null)
        {
            AuthStatus.Text = S.Get("CloudProvider_NoConfigFound");
            ProviderCombo.SelectedIndex = 2; // Folder / Mapped Drive (default local path)
            if (!string.IsNullOrEmpty(snap.DefaultLocalPath))
                TokenPathBox.Text = snap.DefaultLocalPath;
            UpdateProviderUI();
            return;
        }

        for (int i = 0; i < ProviderCombo.Items.Count; i++)
        {
            if (ProviderCombo.Items[i] is ComboBoxItem item && item.Tag as string == snap.Config.Provider)
            {
                ProviderCombo.SelectedIndex = i;
                break;
            }
        }

        if (!string.IsNullOrEmpty(snap.PathTextOverride))
            TokenPathBox.Text = snap.PathTextOverride;
        else if (snap.Config.IsLocal || snap.Config.IsFolder)
        {
            if (!string.IsNullOrEmpty(snap.DefaultLocalPath))
                TokenPathBox.Text = snap.DefaultLocalPath;
        }

        UpdateProviderUI();
        // Use the pre-resolved token status so the dispatcher path never
        // re-enters CheckTokenStatus synchronously on Loaded. Only reach
        // the slow path on later user gestures (Provider change, Browse).
        UpdateAuthStatus(snap.TokenStatus);
    }

    /// <summary>
    /// Sets the path box to the default local storage path: &lt;steamdir&gt;/localcloud.
    /// Synchronous fallback for non-Loaded callers (BrowseToken, provider switch);
    /// the Loaded path uses the pre-resolved snapshot instead.
    /// </summary>
    private void SetDefaultLocalPath()
    {
        var steamPath = Services.SteamDetector.FindSteamPath();
        if (steamPath != null)
            TokenPathBox.Text = Path.Combine(steamPath, "localcloud");
    }

    private void ProviderCombo_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;

        UpdateProviderUI();

        if (ProviderCombo.SelectedItem is ComboBoxItem item)
        {
            var tag = item.Tag as string;
            if (tag == "gdrive")
            {
                TokenPathBox.Text = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "CloudRedirect", "google_tokens.json");
            }
            else if (tag == "onedrive")
            {
                TokenPathBox.Text = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "CloudRedirect", "onedrive_tokens.json");
            }
            else if (tag == "folder")
            {
                SetDefaultLocalPath();
            }
        }

        UpdateAuthStatus();
        // Persist the provider switch (and the path it just set).
        _ = SaveConfigSilent();
    }

    // Auto-save manual path edits when the field loses focus, rather than on
    // every keystroke.
    private void TokenPathBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _ = SaveConfigSilent();
    }

    /// <summary>
    /// Updates labels, enabled state, and hints for the selected provider.
    /// </summary>
    private void UpdateProviderUI()
    {
        if (ProviderCombo.SelectedItem is not ComboBoxItem item) return;

        var tag = item.Tag as string;
        bool needsTokens = tag is "gdrive" or "onedrive";
        bool isFolder = tag == "folder";
        bool needsPath = needsTokens || isFolder;

        TokenPathBox.IsEnabled = needsPath;
        BrowseButton.IsEnabled = needsPath;
        SignInButton.Visibility = needsTokens ? Visibility.Visible : Visibility.Collapsed;
        // Upload in-flight cap is a Google Drive-only throttle.
        UploadInFlightSection.Visibility = tag == "gdrive" ? Visibility.Visible : Visibility.Collapsed;

        // Update labels based on provider type
        if (isFolder)
        {
            PathLabel.Text = S.Get("CloudProvider_SyncFolderPath");
            TokenPathBox.PlaceholderText = S.Get("CloudProvider_SyncFolderPlaceholder");
            PathHint.Text = S.Get("CloudProvider_SyncFolderHint");
        }
        else if (needsTokens)
        {
            PathLabel.Text = S.Get("CloudProvider_TokenFilePath");
            TokenPathBox.PlaceholderText = S.Get("CloudProvider_TokenPlaceholder");
            PathHint.Text = "";
        }
        else
        {
            PathLabel.Text = S.Get("CloudProvider_TokenFilePath");
            TokenPathBox.PlaceholderText = "";
            PathHint.Text = "";
        }

        // Only reserve space for the hint when it actually has text.
        PathHint.Visibility = string.IsNullOrEmpty(PathHint.Text)
            ? Visibility.Collapsed : Visibility.Visible;
    }

    private void BrowseToken_Click(object sender, RoutedEventArgs e)
    {
        var provider = GetSelectedProvider();

        if (provider == "folder")
        {
            var dialog = new Microsoft.Win32.OpenFolderDialog
            {
                Title = S.Get("CloudProvider_SelectSyncFolder"),
                Multiselect = false
            };

            if (!string.IsNullOrEmpty(TokenPathBox.Text) && Directory.Exists(TokenPathBox.Text))
                dialog.InitialDirectory = TokenPathBox.Text;

            if (dialog.ShowDialog() == true)
            {
                TokenPathBox.Text = dialog.FolderName;
                UpdateAuthStatus();
                _ = SaveConfigSilent();
            }
        }
        else
        {
            var dialog = new Microsoft.Win32.OpenFileDialog
            {
                Title = S.Get("CloudProvider_SelectTokenFile"),
                Filter = "JSON files (*.json)|*.json|All files (*.*)|*.*",
                CheckFileExists = false
            };

            if (dialog.ShowDialog() == true)
            {
                TokenPathBox.Text = dialog.FileName;
                UpdateAuthStatus();
                _ = SaveConfigSilent();
            }
        }
    }

    private async void SignIn_Click(object sender, RoutedEventArgs e)
    {
        if (_isAuthenticating) return;

        var provider = GetSelectedProvider();
        if (provider == "folder") return;

        var tokenPath = TokenPathBox.Text?.Trim();
        if (string.IsNullOrEmpty(tokenPath))
        {
            await Services.Dialog.ShowWarningAsync(S.Get("CloudProvider_MissingPath"),
                S.Get("CloudProvider_MissingPathMessage"));
            return;
        }

        _isAuthenticating = true;
        _authCts = new CancellationTokenSource();
        _oauth = new Services.OAuthService();

        SignInButton.IsEnabled = false;
        CancelAuthButton.Visibility = Visibility.Visible;
        ProviderCombo.IsEnabled = false;
        LogBorder.Visibility = Visibility.Visible;
        _logBuffer.Clear();
        LogOutput.Text = "";

        try
        {
            bool success = await _oauth.AuthorizeAsync(
                provider,
                tokenPath,
                msg => Dispatcher.BeginInvoke(() => AppendLog(msg)),
                _authCts.Token);

            if (success)
            {
                // Also save the config so the DLL picks up the new provider + token path
                await SaveConfigSilent();
            }
        }
        catch (OperationCanceledException)
        {
            AppendLog("Authentication cancelled.");
        }
        catch (Exception ex)
        {
            AppendLog($"ERROR: {ex.Message}");
        }
        finally
        {
            _oauth?.Dispose();
            _oauth = null;
            _authCts?.Dispose();
            _authCts = null;
            _isAuthenticating = false;

            SignInButton.IsEnabled = true;
            CancelAuthButton.Visibility = Visibility.Collapsed;
            ProviderCombo.IsEnabled = true;

            UpdateAuthStatus();
        }
    }

    private void CancelAuth_Click(object sender, RoutedEventArgs e)
    {
        _authCts?.Cancel();
        // Don't dispose _oauth here -- the SignIn_Click finally block handles cleanup
        // after the async operation observes cancellation.
    }

    private async Task<bool> SaveConfigSilent()
    {
        var configDir = Services.SteamDetector.GetConfigDir();

        Directory.CreateDirectory(configDir);

        var provider = GetSelectedProvider();
        var tokenPath = TokenPathBox.Text?.Trim() ?? "";

        var configPath = Path.Combine(configDir, "config.json");

        try
        {
            Services.ConfigHelper.SaveConfig(configPath,
                new[] { "provider", "sync_path", "token_path" },
                writer =>
                {
                    writer.WriteString("provider", provider);
                    if (provider == "folder")
                        writer.WriteString("sync_path", tokenPath);
                    else
                        writer.WriteString("token_path", tokenPath);
                });
            return true;
        }
        catch (Exception ex)
        {
            await Services.Dialog.ShowErrorAsync(S.Get("Common_Error"), S.Format("CloudProvider_FailedSaveConfig", ex.Message));
            return false;
        }
    }

    private string GetSelectedProvider()
    {
        if (ProviderCombo.SelectedItem is ComboBoxItem item)
            return item.Tag as string ?? "folder";
        return "folder";
    }

    private void UpdateAuthStatus(Services.TokenStatus? preCheckedStatus = null)
    {
        if (ProviderCombo.SelectedItem is not ComboBoxItem item) return;

        var tag = item.Tag as string;

        if (tag == "folder")
        {
            var folderPath = TokenPathBox.Text?.Trim();
            if (string.IsNullOrEmpty(folderPath))
            {
                AuthStatus.Text = S.Get("CloudProvider_NoSyncFolder");
                AuthIcon.Symbol = Wpf.Ui.Controls.SymbolRegular.ShieldKeyhole24;
            }
            else if (Directory.Exists(folderPath))
            {
                AuthStatus.Text = S.Format("CloudProvider_FolderAccessible", folderPath);
                AuthIcon.Symbol = Wpf.Ui.Controls.SymbolRegular.ShieldCheckmark24;
            }
            else
            {
                AuthStatus.Text = S.Format("CloudProvider_FolderNotFound", folderPath);
                AuthIcon.Symbol = Wpf.Ui.Controls.SymbolRegular.ShieldDismiss24;
            }
            return;
        }

        var tokenPath = TokenPathBox.Text?.Trim();
        if (string.IsNullOrEmpty(tokenPath))
        {
            AuthStatus.Text = S.Get("CloudProvider_NoTokenFilePath");
            AuthIcon.Symbol = Wpf.Ui.Controls.SymbolRegular.ShieldKeyhole24;
            return;
        }

        // preCheckedStatus avoids sync DPAPI/file I/O on Loaded; user-gesture callers accept sync cost.
        var status = preCheckedStatus ?? Services.OAuthService.CheckTokenStatus(tokenPath);
        AuthStatus.Text = status.Message;
        AuthIcon.Symbol = status.IsAuthenticated
            ? Wpf.Ui.Controls.SymbolRegular.ShieldCheckmark24
            : Wpf.Ui.Controls.SymbolRegular.ShieldKeyhole24;
    }

    /// <summary>Reads upload_inflight_mb from config.json, clamped 24..64.
    /// Absent/invalid -> the 24 MB default. Off the UI thread.</summary>
    private static int ReadUploadInFlightMb()
    {
        try
        {
            var path = Services.SteamDetector.GetConfigFilePath();
            if (!File.Exists(path)) return InFlightDefaultMb;

            using var doc = JsonDocument.Parse(File.ReadAllText(path));
            if (doc.RootElement.TryGetProperty("upload_inflight_mb", out var inf) && inf.TryGetInt32(out var mb))
                return Math.Clamp(mb, InFlightMinMb, InFlightMaxMb);
        }
        catch { }
        return InFlightDefaultMb;
    }

    private void ApplyUploadInFlight(int mb)
    {
        _inFlightLoading = true;
        try
        {
            UploadInFlightSlider.Value = Math.Clamp(mb, InFlightMinMb, InFlightMaxMb);
            UpdateUploadInFlightValueLabel();
        }
        finally { _inFlightLoading = false; }
    }

    private void UploadInFlightSlider_Changed(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        UpdateUploadInFlightValueLabel();
        if (_inFlightLoading) return;
        SaveUploadInFlight();
    }

    private void UpdateUploadInFlightValueLabel()
    {
        if (UploadInFlightValue != null)
            UploadInFlightValue.Text = S.Format("CloudProvider_UploadInFlightValue", (int)UploadInFlightSlider.Value);
    }

    /// <summary>Persists upload_inflight_mb (clamped 24..64) into config.json.</summary>
    private void SaveUploadInFlight()
    {
        int mb = Math.Clamp((int)Math.Round(UploadInFlightSlider.Value), InFlightMinMb, InFlightMaxMb);
        Services.ConfigHelper.SaveConfig(Services.SteamDetector.GetConfigFilePath(),
            new[] { "upload_inflight_mb" },
            writer => writer.WriteNumber("upload_inflight_mb", mb));
    }

    private void AppendLog(string message)
    {
        if (_logBuffer.Length > 0)
            _logBuffer.AppendLine();
        _logBuffer.Append(message);
        LogOutput.Text = _logBuffer.ToString();
        LogScroll.ScrollToEnd();
    }
}
