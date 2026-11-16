#!/usr/bin/env python3
from pathlib import Path
import subprocess,hashlib,json,sys,time,shutil
root=Path(__file__).resolve().parents[2]
out=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else root/'build/tests/easel-page-pool'
out.mkdir(parents=True,exist_ok=True)
files=[root/'Sources/ParcCore'/x for x in ['EaselStore.swift','EaselRichText.swift','EaselCanvasInteraction.swift','EaselWebNavigation.swift','FairPlayIdentity.swift']]
files += [root/'Sources/ParcApp'/x for x in ['LocalContentDrop.swift','WebpageEditCommands.swift','EaselAppearance.swift','EaselTextStyle.swift','TextFormatMenu.swift','EaselRichTextCodec.swift','EaselTextAttachment.swift','EaselParagraphEditing.swift','EaselMarkdownEditing.swift','EaselCanvasView.swift','EaselMotion.swift','EaselWebInput.swift','SavedFocus.swift','SadTabContent.swift','EaselBrowserObjects.swift','FairPlayIdentityController.swift','PointerCover.swift','PointingHand.swift','ParcDialog.swift']]
files.append(Path(subprocess.check_output(['python3','-B',str(root/'tests/Support/declarations.py'),str(out/'ParcButtonSpinner.swift'),'ParcButtonSpinner'],text=True).strip()))
files += [root/'tests/EaselPagePool'/x for x in ['EngineBoundary.swift','Tests.swift']]
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
inputs={str(p):sha(p) for p in files}
cmd=['xcrun','swiftc','-warnings-as-errors','-parse-as-library']+[str(p) for p in files]+['-o',str(out/'pool')]
start=time.monotonic();q=subprocess.run(cmd,capture_output=True,text=True);(out/'compile.log').write_text(q.stdout+q.stderr)
result={'command':cmd,'compile':q.returncode,'inputs':inputs,'seconds':time.monotonic()-start,'run':None}
if q.returncode==0:
 q=subprocess.run([str(out/'pool')],capture_output=True,text=True);(out/'run.log').write_text(q.stdout+q.stderr);result['run']=q.returncode
result['allInputsUnchanged']=all(sha(Path(p))==h for p,h in inputs.items());(out/'receipt.json').write_text(json.dumps(result,indent=2)+'\n')
print(q.stdout+q.stderr,flush=True);assert result['allInputsUnchanged'];sys.exit(q.returncode)
