package @package@;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Color;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.WindowInsets;
import android.webkit.*;
import android.widget.*;

public final class MainActivity extends Activity {
    private WebView web;
    private LinearLayout error;
    private ProgressBar progress;
    private ValueCallback<Uri[]> upload;
    private String address;

    @Override public void onCreate(Bundle state) {
        super.onCreate(state);
        address = getPreferences(0).getString("address", @url@);
        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        root.setBackgroundColor(Color.rgb(23, 35, 46));
        if (Build.VERSION.SDK_INT >= 30) {
            getWindow().setDecorFitsSystemWindows(false);
            root.setOnApplyWindowInsetsListener((view, insets) -> {
                android.graphics.Insets bars = insets.getInsets(WindowInsets.Type.systemBars()
                    | WindowInsets.Type.displayCutout() | WindowInsets.Type.ime());
                view.setPadding(bars.left, bars.top, bars.right, bars.bottom);
                return insets;
            });
        }
        LinearLayout toolbar = new LinearLayout(this);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        TextView title = new TextView(this);
        title.setText(@title@);
        title.setTextSize(20);
        title.setTextColor(Color.WHITE);
        title.setPadding(dp(16), 0, 0, 0);
        toolbar.addView(title, new LinearLayout.LayoutParams(0, dp(48), 1));
        title.setGravity(Gravity.CENTER_VERTICAL);
        Button menu = new Button(this);
        menu.setText("⋮");
        menu.setContentDescription(@menuDescription@);
        toolbar.addView(menu, new LinearLayout.LayoutParams(dp(56), dp(48)));
        menu.setOnClickListener(v -> {
            PopupMenu popup = new PopupMenu(this, menu);
            popup.getMenu().add("Reload").setOnMenuItemClickListener(item -> { web.reload(); return true; });
            popup.getMenu().add("Home").setOnMenuItemClickListener(item -> { web.loadUrl(address); return true; });
            popup.getMenu().add(@addressLabel@).setOnMenuItemClickListener(item -> { editAddress(); return true; });
            popup.getMenu().add("Open in browser").setOnMenuItemClickListener(item -> {
                openExternal(Uri.parse(address)); return true;
            });
            popup.show();
        });
        root.addView(toolbar);
        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        root.addView(progress, new LinearLayout.LayoutParams(-1, dp(2)));
        FrameLayout content = new FrameLayout(this);
        root.addView(content, new LinearLayout.LayoutParams(-1, 0, 1));
        web = new WebView(this);
        content.addView(web, new FrameLayout.LayoutParams(-1, -1));
        error = new LinearLayout(this);
        error.setOrientation(LinearLayout.VERTICAL);
        error.setGravity(Gravity.CENTER);
        error.setPadding(dp(24), dp(24), dp(24), dp(24));
        error.setBackgroundColor(Color.rgb(23, 35, 46));
        TextView message = new TextView(this);
        message.setText(@unreachableMessage@);
        message.setTextColor(Color.WHITE);
        message.setGravity(Gravity.CENTER);
        error.addView(message);
        Button retry = new Button(this);
        retry.setText("Reconnect");
        retry.setOnClickListener(v -> web.loadUrl(address));
        error.addView(retry);
        error.setVisibility(View.GONE);
        content.addView(error, new FrameLayout.LayoutParams(-1, -1));
        setContentView(root);
        WebSettings settings = web.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setDomStorageEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(true);
        settings.setMediaPlaybackRequiresUserGesture(false);
        settings.setUseWideViewPort(true);
        settings.setLoadWithOverviewMode(true);
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageStarted(WebView view, String url, android.graphics.Bitmap icon) {
                error.setVisibility(View.GONE);
            }
            @Override public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                Uri uri = request.getUrl();
                Uri home = Uri.parse(address);
                if (("http".equals(uri.getScheme()) || "https".equals(uri.getScheme()))
                    && home.getHost().equalsIgnoreCase(uri.getHost())) return false;
                if (request.isForMainFrame()) openExternal(uri);
                return true;
            }
            @Override public void onReceivedError(WebView view, WebResourceRequest req, WebResourceError failure) {
                if (req.isForMainFrame()) error.setVisibility(View.VISIBLE);
            }
            @Override public void onReceivedHttpError(WebView view, WebResourceRequest req, WebResourceResponse response) {
                if (req.isForMainFrame()) error.setVisibility(View.VISIBLE);
            }
        });
        web.setWebChromeClient(new WebChromeClient() {
            @Override public void onProgressChanged(WebView view, int value) {
                progress.setProgress(value);
                progress.setVisibility(value == 100 ? View.INVISIBLE : View.VISIBLE);
            }
            @Override public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
                if (upload != null) upload.onReceiveValue(null);
                upload = callback;
                Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
                intent.addCategory(Intent.CATEGORY_OPENABLE);
                // Many upload formats (e.g. gcode, 3mf) have no registered Android MIME type.
                intent.setType("*/*");
                intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, params.getMode() == FileChooserParams.MODE_OPEN_MULTIPLE);
                try { startActivityForResult(intent, 1); }
                catch (ActivityNotFoundException e) { upload.onReceiveValue(null); upload = null; }
                return true;
            }
        });
        if (Build.VERSION.SDK_INT >= 33) {
            getOnBackInvokedDispatcher().registerOnBackInvokedCallback(0, this::goBack);
        }
        if (state == null || web.restoreState(state) == null) web.loadUrl(address);
    }

    private int dp(int value) { return Math.round(value * getResources().getDisplayMetrics().density); }
    private void goBack() { if (web.canGoBack()) web.goBack(); else finish(); }
    @Override public void onBackPressed() { goBack(); }
    private void openExternal(Uri uri) {
        if (!"http".equals(uri.getScheme()) && !"https".equals(uri.getScheme())) return;
        try { startActivity(new Intent(Intent.ACTION_VIEW, uri)); }
        catch (ActivityNotFoundException e) { Toast.makeText(this, "No browser installed", Toast.LENGTH_SHORT).show(); }
    }
    private void editAddress() {
        EditText input = new EditText(this);
        input.setSingleLine(true);
        input.setInputType(android.text.InputType.TYPE_CLASS_TEXT | android.text.InputType.TYPE_TEXT_VARIATION_URI);
        input.setText(address);
        AlertDialog dialog = new AlertDialog.Builder(this).setTitle(@addressLabel@).setView(input)
            .setNegativeButton("Cancel", null).setPositiveButton("Save", null).create();
        dialog.setOnShowListener(ignored -> dialog.getButton(AlertDialog.BUTTON_POSITIVE).setOnClickListener(v -> {
            String value = input.getText().toString().trim();
            if (!value.contains("://")) value = "http://" + value;
            Uri uri = Uri.parse(value);
            if ((!"http".equals(uri.getScheme()) && !"https".equals(uri.getScheme()))
                || uri.getHost() == null || uri.getHost().isEmpty() || uri.getUserInfo() != null) {
                input.setError(@addressError@); return;
            }
            address = value;
            getPreferences(0).edit().putString("address", address).apply();
            web.clearHistory();
            web.loadUrl(address);
            dialog.dismiss();
        }));
        dialog.show();
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request == 1 && upload != null) {
            upload.onReceiveValue(WebChromeClient.FileChooserParams.parseResult(result, data));
            upload = null;
        }
    }
    @Override protected void onSaveInstanceState(Bundle state) { web.saveState(state); super.onSaveInstanceState(state); }
    @Override protected void onPause() { web.onPause(); CookieManager.getInstance().flush(); super.onPause(); }
    @Override protected void onResume() { super.onResume(); if (web != null) web.onResume(); }
    @Override protected void onDestroy() {
        if (upload != null) upload.onReceiveValue(null);
        web.destroy();
        super.onDestroy();
    }
}
