// Writes multiple pasteboard flavors in a single atomic transaction.
// pbcopy can only ever hold one flavor per invocation (each call clears the
// pasteboard first), so a second `pbcopy` for a different flavor wipes the
// first one instead of adding to it — hence this separate JXA helper.
ObjC.import('Cocoa');

function run(argv) {
  var htmlFile = argv[0], rtfFile = argv[1], txtFile = argv[2];
  var pb = $.NSPasteboard.generalPasteboard;
  pb.clearContents;

  pb.setDataForType($.NSData.dataWithContentsOfFile(htmlFile), 'public.html');
  pb.setDataForType($.NSData.dataWithContentsOfFile(rtfFile), 'public.rtf');
  pb.setDataForType($.NSData.dataWithContentsOfFile(txtFile), 'public.utf8-plain-text');
}
