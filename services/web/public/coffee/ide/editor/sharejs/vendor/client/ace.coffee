# This is some utility code to connect an ace editor to a sharejs document.

Range = ace.require("ace/range").Range

# Convert an ace delta into an op understood by share.js
applyToShareJS = (editorDoc, delta, doc, fromUndo) ->
  # Get the start position of the range, in no. of characters
  getStartOffsetPosition = (start) ->
    # This is quite inefficient - getLines makes a copy of the entire
    # lines array in the document. It would be nice if we could just
    # access them directly.
    lines = editorDoc.getLines 0, start.row
      
    offset = 0

    for line, i in lines
      offset += if i < start.row
        line.length
      else
        start.column

    # Add the row number to include newlines.
    offset + start.row

  pos = getStartOffsetPosition(delta.start)

  switch delta.action
    when 'insert'
      text = delta.lines.join('\n')
      doc.insert pos, text, fromUndo
      
    when 'remove'
      text = delta.lines.join('\n')
      doc.del pos, text.length, fromUndo

    else throw new Error "unknown action: #{delta.action}"
  
  return

# Attach an ace editor to the document. The editor's contents are replaced
# with the document's contents unless keepEditorContents is true. (In which case the document's
# contents are nuked and replaced with the editor's).
window.sharejs.extendDoc 'attach_ace', (editor, keepEditorContents, maxDocLength) ->
  throw new Error 'Only text documents can be attached to ace' unless @provides['text']

  doc = this
  editorDoc = editor.getSession().getDocument()
  editorDoc.setNewLineMode 'unix'

  check = ->
    window.setTimeout ->
        editorText = editorDoc.getValue()
        otText = doc.getText()

        if editorText != otText
          console.error "Text does not match!"
          console.error "editor: #{editorText}"
          console.error "ot:     #{otText}"
          # Should probably also replace the editor text with the doc snapshot.
      , 0

  if keepEditorContents
    doc.del 0, doc.getText().length
    doc.insert 0, editorDoc.getValue()
  else
    editorDoc.setValue doc.getText()

  check()

  # When we apply ops from sharejs, ace emits edit events. We need to ignore those
  # to prevent an infinite typing loop.
  suppress = false
  
  # Listen for edits in ace
  editorListener = (change) ->
    return if suppress
    
    if maxDocLength? and editorDoc.getValue().length > maxDocLength
        doc.emit "error", new Error("document length is greater than maxDocLength")
        return

    fromUndo = !!(editor.getSession().$fromUndo or editor.getSession().$fromReject)
    
    applyToShareJS editorDoc, change, doc, fromUndo

    check()

  editorDoc.on 'change', editorListener

  # Listen for remote ops on the sharejs document
  docListener = (op) ->
    suppress = true
    applyToDoc editorDoc, op
    suppress = false

    check()


  # Horribly inefficient.
  offsetToPos = (offset) ->
    # Again, very inefficient.
    lines = editorDoc.getAllLines()

    row = 0
    for line, row in lines
      break if offset <= line.length

      # +1 for the newline.
      offset -= lines[row].length + 1

    row:row, column:offset

  doc.on 'insert', (pos, text) ->
    suppress = true
    editorDoc.insert offsetToPos(pos), text
    suppress = false
    check()

  doc.on 'delete', (pos, text) ->
    suppress = true
    range = Range.fromPoints offsetToPos(pos), offsetToPos(pos + text.length)
    editorDoc.remove range
    suppress = false
    check()

  doc.detach_ace = ->
    doc.removeListener 'remoteop', docListener
    editorDoc.removeListener 'change', editorListener
    delete doc.detach_ace

  return

