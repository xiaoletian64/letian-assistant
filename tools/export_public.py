"""Export reviewed source only, never a Git history or local build state."""
import argparse
import pathlib
import re
import shutil
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
ROOT_FILES = {'AGENTS.md', 'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml', 'README.md', 'LICENSE', '.gitignore', 'THIRD_PARTY_NOTICES.md'}
PREFIXES = ('licenses/', 'lib/', 'assets/', 'test/', 'android/app/', 'android/gradle/', 'ios/Runner/', 'ios/RunnerTests/', 'ios/Runner.xcodeproj/', 'ios/Runner.xcworkspace/', 'third_party/flyer_chat_text_message/', 'server/monitor/', 'server/quota_history/', 'tools/', '.github/workflows/')
EXTRA = {'android/build.gradle', 'android/settings.gradle', 'android/gradle.properties', 'android/gradlew', 'android/gradlew.bat', 'ios/Flutter/Debug.xcconfig', 'ios/Flutter/Release.xcconfig', 'ios/Flutter/AppFrameworkInfo.plist', 'ios/.gitignore', 'docs/PUBLIC-BUILD.md'}
DENIED_PARTS = {'.git', '.dart_tool', 'build', 'Pods', '.symlinks', 'ephemeral', '__pycache__', 'xcuserdata', 'node_modules'}
BINARY = {'.png', '.jar'}
PRIVATE = re.compile(rb'https?://[^\s\"\']+\.site\b|(?<![\w.])(?!(?:127\.0\.0\.1|0\.0\.0\.0)\b)(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?![\w.])|/Users/[A-Za-z0-9_.-]+|/root/\.local|-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|[A-Za-z0-9_-]+@[A-Za-z0-9.-]+\.(?:com|cn|net)\b')

def allowed(path):
    name = path.as_posix()
    if any(x in DENIED_PARTS for x in path.parts): return False
    if '.bak' in path.name or path.name.endswith(('~','.log','.pyc','.iml','.ipa','.apk','.p12','.pem','.key','.cer','.mobileprovision')): return False
    if path.name in {'local.properties','key.properties','Generated.xcconfig','GeneratedPluginRegistrant.h','GeneratedPluginRegistrant.m','flutter_export_environment.sh','.flutter-plugins-dependencies'}: return False
    return name in ROOT_FILES or name in EXTRA or name.startswith(PREFIXES)

def scan(path, tracked=False):
    findings = []
    if tracked:
        names=subprocess.run(['git','-C',str(path),'ls-files','-z'],check=True,capture_output=True).stdout.decode().split('\0')
        files=(path/name for name in names if name)
    else:
        files=path.rglob('*')
    for p in files:
        if p.is_symlink(): findings.append(str(p.relative_to(path))+': symlink rejected'); continue
        if not p.is_file(): continue
        rel = p.relative_to(path)
        if not allowed(rel): findings.append(str(rel) + ': unexpected file'); continue
        raw = p.read_bytes()
        if PRIVATE.search(raw): findings.append(str(rel) + ': private identifier or credential pattern')
        if p.suffix == '.jar':
            with zipfile.ZipFile(p) as z:
                if any(PRIVATE.search(z.read(n)) for n in z.namelist() if not n.endswith('/')): findings.append(str(rel) + ': private archive content')
        elif b'\0' in raw and p.suffix not in BINARY:
            findings.append(str(rel) + ': unreviewed binary')
    return findings

def export(destination):
    destination = destination.resolve()
    if destination == ROOT or ROOT in destination.parents: raise ValueError('export outside source tree')
    if destination.exists() and any(destination.iterdir()): raise ValueError('destination must be empty; no old history')
    destination.mkdir(parents=True, exist_ok=True)
    for src in ROOT.rglob('*'):
        if src.is_file() and not src.is_symlink() and allowed(src.relative_to(ROOT)):
            dst=destination/src.relative_to(ROOT); dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
    issues=scan(destination)
    if issues: raise ValueError('Privacy review required:\n'+'\n'.join(issues))
    return sum(p.is_file() for p in destination.rglob('*'))

if __name__ == '__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--output',type=pathlib.Path); parser.add_argument('--scan',type=pathlib.Path); parser.add_argument('--tracked',action='store_true')
    args=parser.parse_args()
    if args.scan:
        issues=scan(args.scan,tracked=args.tracked); print('\n'.join(issues) if issues else 'Source privacy scan passed'); raise SystemExit(bool(issues))
    if not args.output: parser.error('--output or --scan required')
    print('Exported',export(args.output),'reviewable source files')
