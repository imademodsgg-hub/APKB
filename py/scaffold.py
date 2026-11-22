#!/usr/bin/env python3
"""APKB project scaffolder.

  scaffold.py <style> <out_dir> <app_name> <package> [message]

styles: flat | gradle | eclipse
Creates a small but complete raw-Java Android app (layout, strings, colors,
drawables, asset, launcher icon) so the whole pipeline is exercised.
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import icon  # noqa: E402


def esc(s):
    s = s.replace('\\', '\\\\').replace("'", "\\'").replace('"', '\\"')
    s = s.replace('&', '&amp;').replace('<', '&lt;')
    if s[:1] in '@?':
        s = '\\' + s
    return s


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8') as f:
        f.write(text)


def main(style, out, name, pkg, message):
    if style == 'gradle':
        base = os.path.join(out, 'app', 'src', 'main')
        java_dir = os.path.join(base, 'java', *pkg.split('.'))
        manifest = os.path.join(base, 'AndroidManifest.xml')
        res = os.path.join(base, 'res')
        assets = os.path.join(base, 'assets')
        w(os.path.join(out, 'app', 'build.gradle'),
          'android {\n    namespace "%s"\n    defaultConfig {\n        applicationId "%s"\n'
          '        minSdk 21\n        targetSdk 34\n        versionCode 1\n        versionName "1.0"\n    }\n}\n' % (pkg, pkg))
        w(os.path.join(out, 'settings.gradle'), "include ':app'\n")
    elif style == 'eclipse':
        java_dir = os.path.join(out, 'src', *pkg.split('.'))
        manifest = os.path.join(out, 'AndroidManifest.xml')
        res = os.path.join(out, 'res')
        assets = os.path.join(out, 'assets')
        w(os.path.join(out, 'project.properties'), 'target=android-34\n')
        os.makedirs(os.path.join(out, 'libs'), exist_ok=True)
    else:
        java_dir = os.path.join(out, 'src', *pkg.split('.'))
        manifest = os.path.join(out, 'AndroidManifest.xml')
        res = os.path.join(out, 'res')
        assets = os.path.join(out, 'assets')

    w(manifest, '''<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="%s"
    android:versionCode="1"
    android:versionName="1.0">

    <uses-sdk android:minSdkVersion="21" android:targetSdkVersion="34"/>

    <application
        android:label="@string/app_name"
        android:icon="@mipmap/ic_launcher"
        android:theme="@style/AppTheme">
        <activity android:name=".MainActivity" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
    </application>
</manifest>
''' % pkg)

    w(os.path.join(java_dir, 'MainActivity.java'), '''package %s;

import android.app.Activity;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.widget.Button;
import android.widget.TextView;
import android.widget.Toast;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;

public class MainActivity extends Activity {

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);

        TextView title = (TextView) findViewById(R.id.title);
        title.setText(R.string.hello);

        TextView info = (TextView) findViewById(R.id.info);
        info.setText("Device: " + Build.MANUFACTURER + " " + Build.MODEL
                + "\\nAndroid " + Build.VERSION.RELEASE + " (API " + Build.VERSION.SDK_INT + ")"
                + "\\n\\n" + readAsset("about.txt"));

        Button button = (Button) findViewById(R.id.button);
        button.setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                Toast.makeText(MainActivity.this, R.string.toast, Toast.LENGTH_SHORT).show();
            }
        });
    }

    private String readAsset(String file) {
        try {
            InputStream in = getAssets().open(file);
            ByteArrayOutputStream out = new ByteArrayOutputStream();
            byte[] buf = new byte[1024];
            int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            in.close();
            return out.toString("UTF-8");
        } catch (Exception e) {
            return "(asset not found)";
        }
    }
}
''' % pkg)

    w(os.path.join(res, 'layout', 'activity_main.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:background="@drawable/bg_gradient"
    android:gravity="center"
    android:orientation="vertical"
    android:padding="24dp">

    <TextView
        android:id="@+id/title"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:gravity="center"
        android:textColor="@color/text_main"
        android:textSize="26sp"
        android:textStyle="bold"/>

    <TextView
        android:id="@+id/info"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="20dp"
        android:gravity="center"
        android:textColor="@color/text_dim"
        android:textSize="14sp"/>

    <Button
        android:id="@+id/button"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginTop="28dp"
        android:text="@string/button"/>
</LinearLayout>
''')
    w(os.path.join(res, 'values', 'strings.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">%s</string>
    <string name="hello">%s</string>
    <string name="button">Test the toast</string>
    <string name="toast">Built with APKB - raw Java, no Gradle!</string>
</resources>
''' % (esc(name), esc(message)))
    w(os.path.join(res, 'values', 'colors.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="bg_start">#0F172A</color>
    <color name="bg_end">#312E81</color>
    <color name="text_main">#FFFFFF</color>
    <color name="text_dim">#A5B4FC</color>
</resources>
''')
    w(os.path.join(res, 'values', 'styles.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="AppTheme" parent="@android:style/Theme.Material.NoActionBar"/>
</resources>
''')
    w(os.path.join(res, 'drawable', 'bg_gradient.xml'), '''<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient
        android:angle="270"
        android:startColor="@color/bg_start"
        android:endColor="@color/bg_end"/>
</shape>
''')
    w(os.path.join(assets, 'about.txt'),
      'This text file lives in assets/ and was read at runtime.\nResources, layout, drawables and assets all work.')
    icon.install_icon('-', res, 'ic_launcher')
    print('created %s project at %s' % (style, out))
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 5:
        print(__doc__)
        sys.exit(2)
    msg = sys.argv[5] if len(sys.argv) > 5 else "Hello Android!, I'm APKB!"
    sys.exit(main(sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], msg))
