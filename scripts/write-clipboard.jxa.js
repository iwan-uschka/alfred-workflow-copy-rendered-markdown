// Writes multiple pasteboard flavors in a single atomic transaction.
// pbcopy can only ever hold one flavor per invocation (each call clears the
// pasteboard first), so a second `pbcopy` for a different flavor wipes the
// first one instead of adding to it — hence this separate JXA helper.
ObjC.import('Cocoa');

function run(argv) {
  var htmlFile = argv[0], rtfFile = argv[1], txtFile = argv[2];
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;

  var htmlData = $.NSData.dataWithContentsOfFile(htmlFile);
  var rtfData = $.NSData.dataWithContentsOfFile(rtfFile);
  var txtData = $.NSData.dataWithContentsOfFile(txtFile);
  // A failed read bridges to an ObjC nil wrapped in a JS object, which is
  // always truthy (`!data` never catches it) — `.isNil()` is the correct
  // nil test for a JXA-bridged Cocoa return value.
  if (htmlData.isNil() || rtfData.isNil() || txtData.isNil()) {
    throw new Error('failed to read one or more clipboard flavor files');
  }

  if (!pb.setDataForType(htmlData, 'public.html')) {
    throw new Error('setDataForType failed for public.html');
  }
  if (!pb.setDataForType(rtfData, 'public.rtf')) {
    throw new Error('setDataForType failed for public.rtf');
  }
  if (!pb.setDataForType(txtData, 'public.utf8-plain-text')) {
    throw new Error('setDataForType failed for public.utf8-plain-text');
  }
}
