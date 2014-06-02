_= require 'underscore'
async = require 'async'
{Evernote} = require 'evernote'
fs = require 'fs'
slug = require 'slug'

dir = "#{__dirname}/.evernote_cache"
asset_dir = "#{__dirname}/../assets"
try
  oauthAccessToken = fs.readFileSync('.access_token', 'utf-8').trim()
catch
  oauthAccessToken = ''
notebookGuid = '8bc2be03-ae09-4ceb-9bfe-f9271ea96766'

try fs.mkdirSync dir

seqNums = {}
tags = {}

updateSeqNum = (guid, seqNum) ->
  seqNums[guid] = seqNum if not seqNums[guid] or seqNums[guid] < seqNum

readSeqNums = ->
  files = fs.readdirSync dir
  for file in files
    if /(.*):(.*)\.enml/.test file
      updateSeqNum RegExp.$1, Number(RegExp.$2)
readSeqNums()

noteStore = new Evernote.Client(token: oauthAccessToken, sandbox: false).getNoteStore()

getResource = (mime, guid, callback) ->
  ext = switch mime
    when 'image/jpeg' then '.jpg'
    when 'image/png' then '.png'
    else ''
  path = "/evernote/#{guid}#{ext}"
  return callback null, path if fs.existsSync asset_dir + path
  console.log 'Get resource: ' + guid
  noteStore.getResource guid, true, false, false, false, (error, data) ->
    buffer = new Buffer data.data._body
    fs.writeFileSync asset_dir + path, buffer
    callback null, path

uintArrayToHash = (array) ->
  str = ''
  for i in array
    c = i.toString(16)
    if c.length is 1
      str += '0'
    str += c
  return str

processMarkups = (content) ->
  while (pos = content.indexOf 'http://markup.croquis.com')>=0
    start = content.lastIndexOf '<a', pos
    end = content.indexOf '</a>', pos
    if start < 0 or end < 0
      break
    markup = content.substr(start, end-start+4)
    markup = markup.replace /<[^>]*>/g, ''
    content = content.substr(0, start) + markup + content.substr(end+4)
  return content

getNoteContent = (note, callback) ->
  console.log 'Get note: ' + note.title + ',' + note.guid + ':' + note.updateSequenceNum
  noteStore.getNote note.guid, true, false, false, false, (error, data) ->
    console.log 'getNoteContent: ' + JSON.stringify(error) if error
    content = data.content

    content = processMarkups content

    medias = content.match(/<en-media.*?>(<\/en-media>)?/g) or []
    async.forEach medias, (media, callback) ->
      /hash="(.*?)"/.test media
      hash = RegExp.$1
      res = _.find data.resources, (r) ->
        return uintArrayToHash(r.data.bodyHash) is hash
      return callback null if not res
      getResource res.mime, res.guid, (error, path) ->
        content = content.replace media, "<img src='{{ ASSET_PATH }}#{path}'>"
        callback null
    , (error) ->
      callback content

getNote = (note, callback) ->
  filename = "#{dir}/#{note.guid}:#{note.updateSequenceNum}.enml"
  return callback true if fs.existsSync filename
  getNoteContent note, (content) ->
    return callback false if not content
    fs.writeFileSync filename, content
    callback true

getAllNotes = (callback) ->
  filter = new Evernote.NoteFilter notebookGuid: notebookGuid
  result_spec = new Evernote.NotesMetadataResultSpec includeTitle: true, includeCreated: true, includeUpdated: true, includeUpdateSequenceNum: true, includeTagGuids: true
  noteStore.findNotesMetadata filter, 0, 10000, result_spec, (error, response) ->
    return callback error if error
    notes = response.notes
    notes = _.filter notes, (note) -> note.tagGuids?.length > 0
    async.forEachSeries notes, (note, next) ->
      return next null if seqNums[note.guid] is note.updateSequenceNum
      getNote note, (success) ->
        return next null if not success
        next null
    , (error) ->
      callback error, notes

getTag = (tagGuid, callback) ->
  return callback null, tags[tagGuid] if tags[tagGuid]
  noteStore.getTag tagGuid, (error, tag) ->
    return callback null if error
    callback null, tags[tagGuid] = tag.name

cutBeforeHR = (content) ->
  return ['', content]
#  hr_pos = content.indexOf '<hr/>'
#  return ['', content] if hr_pos<0
#
#  elements = content.substr(0, hr_pos).split('<')[1..].reverse()
#  elements_meta = []
#  elements_content = []
#  depth = 1
#  all_meta = false
#  for element in elements
#    if element[0] is '/'
#      depth++
#    else
#      depth--
#    if all_meta or depth > 0
#      elements_meta.push element
#    else
#      elements_content.push element
#    all_meta = true if depth is 0
#
#  meta_str = '<'+elements_meta.reverse().join('<')
#  content = '<'+elements_content.reverse().join('<') + content.substr(hr_pos+5)
#
#  return [meta_str, content]

parseMeta = (meta_str) ->
  meta = {}
  meta_str = meta_str.replace /<[^>]*>/g, '\n'
  for line in meta_str.split '\n'
    if /(.*):(.*)/.test line
      meta[RegExp.$1.trim()] = RegExp.$2.trim()
  return meta

readNote = (filename) ->
  content = fs.readFileSync filename, 'utf-8'
  /<en-note.*?>([\s\S]*)<\/en-note>/.test content
  [meta_str, content] = cutBeforeHR RegExp.$1
  meta = parseMeta meta_str
  return [meta, content]

datePad = (num) ->
  return '0' + num if num<10
  return num

getCountForDate = (path, date) ->
  count = 1
  files = fs.readdirSync path
  for file in files
    count++ if file.substr(0, date.length) is date
  return count

initial_table = ['g','kk','n','d','tt','r','m','b','pp','s','ss','','j','jj','ch','k','t','p','h']
medial_table = ['a','ae','ya','yae','eo','e','yeo','ye','o','wa','wae','oe','yo','u','wo','we','wi','yu','eu','ui','i']
final_table = ['','k','k','k','n','n','n','t','l','l','l','l','l','l','l','l','m','p','p','t','t','ng','t','t','k','t','p','t']

romanize = (str) ->
  str = str.replace /./g, (ch) ->
    code = ch.charCodeAt(0)
    if code>=0xAC00 and code<=0xD7AF
      code = code - 0xAC00
      initial = Math.floor code / (21*28)
      medial = Math.floor (code - initial*21*28)/28
      final = code % 28
      ch = initial_table[initial]+medial_table[medial]+final_table[final]
    return ch
  return str

writePost = (note, tags, meta, content) ->
  lang_tags = tags.filter (tag) -> tag.substr(0,5) is 'lang:'
  lang = lang_tags[0]?.substr 5
  return if not lang
  author_tags = tags.filter (tag) -> tag.substr(0,7) is 'author:'
  author = author_tags[0]?.substr 7
  return if not author
  tags = tags.filter (tag) -> not (tag.substr(0,5) is 'lang:' or tag.substr(0,7) is 'author:')

  front = []
  front.push '---'
  front.push "layout: post.#{lang}"
  front.push 'category: ' + lang
  front.push "title: '#{note.title}'"
  front.push 'tags: [' + tags.join(', ') + ']'
  front.push 'author: ' + author
  front.push '---'
  front.push '{% include setup %}'
  front.push ''
  content = front.join('\n') + content

  url_path = meta.url_path or romanize note.title
  url_path = slug url_path
  url_path = url_path.replace /[*+~.()'"!:@]/g, ''

  created = new Date(note.created)
  path = '../_posts/evernote'
  date = "#{created.getFullYear()}-#{datePad created.getMonth()+1}-#{datePad created.getDate()}"
  count = getCountForDate path, date
  filename = "#{path}/#{date}-#{count}-#{url_path}.html"

  fs.writeFileSync filename, content

getAllNotes (error, notes) ->
  if error
    console.log 'getAllNotes fail', error
    return
  notes.sort (a, b) -> return a.created - b.created
  async.forEachSeries notes, (note, next) ->
    filename = "#{dir}/#{note.guid}:#{note.updateSequenceNum}.enml"
    return next null if not fs.existsSync filename
    async.map note.tagGuids, getTag, (error, tags) ->
      [meta, content] = readNote filename
      writePost note, tags, meta, content
      next null
  , (error) ->
