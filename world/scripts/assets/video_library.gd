extends RefCounted
## Only explicitly imported local files are exposed to scene records and agents.

const MAX_BYTES := 512 * 1024 * 1024
const EXTENSIONS := ["ogv", "mp4", "m4v", "mov", "webm", "mkv"]
static var directory := "user://videos"
static var _id := RegEx.create_from_string("^[a-f0-9]{32}$")

static func installed() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not DirAccess.dir_exists_absolute(directory):
		return result
	for name: String in DirAccess.get_files_at(directory):
		var id := name.get_basename()
		if name.get_extension() != "ogv" or not valid_id(id):
			continue
		var file := FileAccess.open(directory.path_join(id + ".name"), FileAccess.READ)
		var title := file.get_as_text() if file and file.get_length() <= 1024 else "Video " + id.left(8)
		result.append({"id": id, "name": title})
	return result

static func valid_id(id: String) -> bool:
	return _id.search(id) != null

static func path_for(id: String) -> String:
	if not valid_id(id):
		return ""
	var path := directory.path_join(id + ".ogv")
	return path if FileAccess.file_exists(path) else ""

static func prepare(source: String) -> Dictionary:
	var extension := source.get_extension().to_lower()
	var file := FileAccess.open(source, FileAccess.READ)
	if extension not in EXTENSIONS or file == null or file.get_length() <= 0 or file.get_length() > MAX_BYTES:
		return _error("Choose a local video under 512 MB.")
	file.close()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		return _error("Could not create the local video library.")
	var id := Crypto.new().generate_random_bytes(16).hex_encode()
	return {"ok": true, "source": source, "id": id, "extension": extension,
		"stage": ProjectSettings.globalize_path(directory.path_join("." + id + ".ogv"))}

static func convert(job: Dictionary) -> int:
	var args := PackedStringArray(["-nostdin", "-loglevel", "error", "-threads", "2", "-filter_threads", "1",
		"-protocol_whitelist", "file", "-f", "matroska" if job.extension in ["webm", "mkv"] else "mov",
		"-i", job.source, "-map", "0:v:0", "-map", "0:a:0?", "-vf",
		"scale=min(iw\\,960):min(ih\\,540):force_original_aspect_ratio=decrease:force_divisible_by=2,fps=min(source_fps\\,30)",
		"-c:v", "libtheora", "-threads", "2", "-q:v", "6", "-c:a", "libvorbis", "-fs", str(MAX_BYTES), job.stage])
	var executable := OS.get_environment("EUCLID_FFMPEG_BIN")
	if executable.is_empty():
		executable = "ffmpeg.exe" if OS.get_name() == "Windows" else "ffmpeg"
	return OS.create_process(executable, args, false)

static func finish(job: Dictionary, converted: bool) -> Dictionary:
	var stage: String = job.stage
	var id: String = job.id
	if not converted:
		DirAccess.remove_absolute(stage)
		return _error("Could not convert this video. Use an OGV file or install FFmpeg for other formats.")
	var header := FileAccess.open(stage, FileAccess.READ)
	if header == null or header.get_length() > MAX_BYTES or not _is_theora(header.get_buffer(8192)):
		if header:
			header.close()
		DirAccess.remove_absolute(stage)
		return _error("This file does not contain an Ogg Theora video.")
	header.close()
	var name: String = job.source.get_file().get_basename().replace("\n", " ").replace("\r", " ").left(80)
	var metadata := FileAccess.open(directory.path_join(id + ".name"), FileAccess.WRITE)
	if metadata:
		metadata.store_string(name)
		metadata.close()
	if DirAccess.rename_absolute(stage, directory.path_join(id + ".ogv")) != OK:
		DirAccess.remove_absolute(stage)
		DirAccess.remove_absolute(directory.path_join(id + ".name"))
		return _error("Could not save the video.")
	return {"ok": true, "id": id, "name": name}

static func _is_theora(header: PackedByteArray) -> bool:
	var offset := 0
	var signature := PackedByteArray([0x80, 116, 104, 101, 111, 114, 97])
	while offset + 27 <= header.size() and header.slice(offset, offset + 4).get_string_from_ascii() == "OggS":
		var segment_count := int(header[offset + 26])
		var packet := offset + 27 + segment_count
		if packet > header.size():
			return false
		# A Theora identification packet starts a logical stream.
		if (header[offset + 5] & 2) != 0 and segment_count > 0 and header[packet - segment_count] >= signature.size():
			if header.slice(packet, packet + signature.size()) == signature:
				return true
		var payload_size := 0
		for index in range(offset + 27, packet):
			payload_size += header[index]
		offset = packet + payload_size
	return false

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
