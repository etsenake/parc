#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,subprocess,time,argparse
p=argparse.ArgumentParser();p.add_argument('--output',type=Path);args=p.parse_args()
c=Path(__file__).resolve().parents[2];out=(args.output or c/'build/tests/local-content-drop').resolve();out.mkdir(parents=True,exist_ok=True)
app=['LocalContentDrop','ExternalSplitDropView','SplitDropPlaceholderCard','SadTabContent','SidebarIconCatalog','SplitDropGeometry','ParcSplitView','PageCardShadow','SplitMarginHandle','SplitPaneHighlight','WebpageEditCommands','EaselTextStyle','TextFormatMenu','EaselRichTextCodec','EaselTextAttachment','EaselParagraphEditing','EaselMarkdownEditing','EaselCanvasView','NoteKeyboardEditing','NoteDocumentPresentation','NotePaper','NoteImageImport','NoteFormatting','NoteSelectionFormatting','NoteEditorViewController','NoteAccessibility','NoteMotion','EaselAppearance','EaselMotion','PointingHand','PointerCover','ParcDialog']
files=sorted(c.glob('Sources/ParcCore/*.swift'))+[c/f'Sources/ParcApp/{n}.swift' for n in app]+[Path(subprocess.check_output(['python3','-B',str(c/'tests/Support/declarations.py'),str(out/'ParcButtonSpinner.swift'),'ParcButtonSpinner'],text=True).strip()),c/'tests/NativeContentDrop/LocalEditorTests.swift']
h=c/'Engine/ParcNative/content_drop_router.h';mm=c/'Engine/ParcNative/content_drop_router.mm';bridge=c/'Engine/ParcNative/content_drop_bridge.mm';bridge_header=c/'Engine/ParcNative/content_drop_bridge.h';inputs=files+[h,mm,bridge,bridge_header,Path(__file__).resolve()]
sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest();hashes={(str(f.relative_to(c)) if f.is_relative_to(c) else str(f)):sha(f) for f in inputs}
vfs=out/'component.vfs.json';vfs.write_text(json.dumps({'version':0,'roots':[{'type':'file','name':str(out/'ui/base/cocoa/content_drop_router.h'),'external-contents':str(h)}]}))
imports=out/'imports.h';imports.write_text('#import \"'+str(h)+'\"\n#import \"'+str(bridge_header)+'\"\n')
commands=[['xcrun','clang++','-std=c++20','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-ivfsoverlay',str(vfs),'-I'+str(out),'-c',str(mm),'-o',str(out/'router.o')], ['xcrun','clang++','-std=c++20','-fobjc-arc','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-ivfsoverlay',str(vfs),'-I'+str(out),'-c',str(bridge),'-o',str(out/'bridge.o')], ['xcrun','swiftc','-warnings-as-errors','-whole-module-optimization','-parse-as-library','-import-objc-header',str(imports)]+[str(f) for f in files]+[str(out/'router.o'),str(out/'bridge.o'),'-lc++','-o',str(out/'local-editor-drops')], [str(out/'local-editor-drops')]]
started=time.monotonic();output=b'';rc=0
for cmd in commands:
 result=subprocess.run(cmd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT);output+=result.stdout;rc=result.returncode
 if rc:break
(out/'output.log').write_bytes(output);(out/'receipt.json').write_text(json.dumps(dict(returncode=rc,seconds=time.monotonic()-started,inputs=hashes,unchanged=all(sha(c/f)==s for f,s in hashes.items()),commands=commands,output=output.decode()),indent=2)+'\n')
print(output.decode());raise SystemExit(rc)
