require 'mp.options'
local utils = require "mp.utils"
local detect = {
	archive = false,
	err = false,
	image = false,
	init = false,
	p7zip = false,
	rar = false,
	tar = false,
	zip = false,
}
local opts = {
	aspect_ratio = 16/9,
	double = false,
	manga = true,
	offset = 20,
	pages = 10,
	worker = true,
}
local dir
local filearray = {}
local filedims = {}
local index = 0
local init_arg
local length
local names = nil
local root
local valid_width
local workers = {}

function check_archive(path)
	if string.find(path, "archive://") == nil then
		return false
	else
		return true
	end
end

function check_aspect_ratio(a, b)
	local m = a[0]+b[0]
	local n
	if a[1] > b[1] then
		n = a[1]
	else
		n = b[1]
	end
	if m/n <= opts.aspect_ratio then
		return true
	else
		return false
	end
end

function check_if_p7zip()
	local archive = string.gsub(root, ".*/", "")
	local p7zip = io.popen("7z t "..archive.." | grep 'Type'")
	io.input(p7zip)
	local str = io.read()
	io.close()
	if string.find(str, "Type = zip") == nil then
		detect.p7zip = true
		return true
	end
	return false
end

function check_if_rar()
	local archive = string.gsub(root, ".*/", "")
	local rar = io.popen("7z t "..archive.." | grep 'Type'")
	io.input(rar)
	local str = io.read()
	io.close()
	if string.find(str, "Type = Rar") or string.find(str, "Type = rar") then
		detect.rar = true
		return true
	end
	return false
end

function check_if_tar()
	if string.find(root, "%.tar") then
		detect.tar = true
		return true
	end
	return false
end

function check_if_zip()
	local archive = string.gsub(root, ".*/", "")
	local zip = io.popen("zip --test "..archive)
	io.input(zip)
	local str = io.read()
	io.close()
	if string.find(str, "probably not a zip file") == nil then
		detect.zip = true
		return true
	end
	return false
end

function check_archive_type_brute()
	local type_found
	while not type_found do
		type_found = check_if_zip()
		type_found = check_if_tar()
		type_found = check_if_rar()
		type_found = check_if_p7zip()
		break
	end
	return type_found
end

function check_archive_type()
	local type_found
	if string.find(root, ".zip") then
		type_found = check_if_zip()
	elseif string.find(root, ".tar") then
		type_found = check_if_tar()
	elseif string.find(root, ".rar") then
		type_found = check_if_rar()
	elseif string.find(root, ".7z") then
		type_found = check_if_p7zip()
	else
		check_archive_type_brute()
	end
	return type_found
end

function check_image()
	audio = mp.get_property("audio-params")
	frame_count = mp.get_property("estimated-frame-count")
	if audio == nil and (frame_count == "1" or frame_count == "0" or frame_count == nil) then
		return true
	else
		return false
	end
end

function escape_special_characters(str)
	str = string.gsub(str, " ", "\\ ")
	str = string.gsub(str, "%(", "\\(")
	str = string.gsub(str, "%)", "\\)")
	str = string.gsub(str, "%[", "\\[")
	str = string.gsub(str, "%]", "\\]")
	return str
end

function file_exists(name)
	local f = io.open(name, "r")
	if f == nil then
		return false
	else
		io.close(f)
		return true
	end
end

function strip_file_ext(str)
	local pos = 0
	local ext = string.byte(".")
	for i = 1, #str do
		if str:byte(i) == ext then
			pos = i
		end
	end
	if pos == 0 then
		return str
	else
		local stripped = string.sub(str, 1, pos - 1)
		return stripped
	end
end

function generate_name(cur_page, next_page)
	local cur_base = string.gsub(cur_page, ".*/", "")
	cur_base = strip_file_ext(cur_base)
	local next_base = string.gsub(next_page, ".*/", "")
	next_base = strip_file_ext(next_base)
	local name = cur_base.."-"..next_base..".png"
	return name
end

function get_filelist(path)
	local filelist
	if detect.archive then
		local archive = string.gsub(path, ".*/", "")
		if detect.p7zip then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif detect.rar then
			filelist = io.popen("7z l -slt "..archive.. " | grep 'Path =' | grep -v "..archive.." | sed 's/Path = //g'")
		elseif detect.tar then
			filelist = io.popen("tar -tf "..archive.. " | sort")
		elseif detect.zip then
			filelist = io.popen("zipinfo -1 "..archive)
		end
	else
		filelist = io.popen("ls "..path)
	end
	return filelist
end

function get_root(path)
	local root
	if detect.archive then
		root = string.gsub(path, "|.*", "")
		root = escape_special_characters(root)
	else
		root = string.gsub(path, "/.*", "")
		root = escape_special_characters(root)
	end
	return root
end

function str_split(str, delim)
	local split = {}
	local i = 0
	for token in string.gmatch(str, "([^"..delim.."]+)") do
		split[i] = token
		i = i + 1
	end
	return split
end

function get_dims(page)
	local dims = {}
	local p
	local str
	if detect.archive then
		local archive = string.gsub(root, ".*/", "")
		if detect.p7zip then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif detect.rar then
			p = io.popen("7z e -so "..archive.." "..page.." | identify -")
		elseif detect.tar then
			p = io.popen("tar -xOf "..archive.." "..page.." | identify -")
		elseif detect.zip then
			p = io.popen("unzip -p "..archive.." "..page.." | identify -")
		end
		io.input(p)
		str = io.read()
		if str == nil then
			dims = nil
		else
			local i, j = string.find(str, "[0-9]+x[0-9]+")
			local sub = string.sub(str, i, j)
			dims = str_split(sub, "x")
		end
	else
		local path = utils.join_path(root, page)
		p = io.popen("identify -format '%w,%h' "..path)
		io.input(p)
		str = io.read()
		io.close()
		if str == nil then
			dims = nil
		else
			dims = str_split(str, ",")
		end
	end
	return dims
end

function double_page()
	local cur_page = filearray[index]
	local next_page = filearray[index + 1]
	local name = generate_name(cur_page, next_page)
	if file_exists(name) then
		mp.commandv("loadfile", name, "replace")
		return
	end
	if names == nil then
		names = name
	else
		names = names.." "..name
	end
	if detect.archive then
		local archive = string.gsub(root, ".*/", "")
		if detect.p7zip then
			os.execute("7z e "..archive.." "..cur_page.." "..next_page)
		elseif detect.rar then
			os.execute("7z e "..archive.." "..cur_page.." "..next_page)
		elseif detect.tar then
			p = io.popen("tar -xf "..archive.." "..cur_page.." "..next_page)
		elseif detect.zip then
			os.execute("unzip "..archive.." "..cur_page.." "..next_page)
		end
	else
		cur_page = utils.join_path(root, cur_page)
		next_page = utils.join_path(root, next_page)
	end
	if opts.manga then
		os.execute("convert "..next_page.." "..cur_page.." +append "..name)
	else
		os.execute("convert "..cur_page.." "..next_page.." +append "..name)
	end
	if detect.archive then
		os.execute("rm "..cur_page.." "..next_page)
	end
	mp.commandv("loadfile", name, "replace")
end

function single_page()
	local page = filearray[index]
	if detect.archive then
		local noescaperoot = string.gsub(root, "\\", "")
		local noescapepage = string.gsub(page, "\\", "")
		mp.commandv("loadfile", noescaperoot.."|"..noescapepage, "replace")
	else
		local path = utils.join_path(root, page)
		path = string.gsub(path, "\\", "")
		mp.commandv("loadfile", path, "replace")
	end
end

function update_worker_index()
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "worker-index", tostring(index))
		i = i + 1
	end
end

function change_page(amount)
	index = index + amount
	if index < 0 then
		index = 0
		change_page(0)
		return
	end
	if opts.double then
		if index > length - 2 then
			index = length - 2
		end
		valid_width = check_aspect_ratio(filedims[index], filedims[index+1])
		if not valid_width then
			if amount < -1 then
				index = index + 1
			end
			single_page()
		else
			double_page()
		end
	else
		if index > length - 1 then
			index = length - 1
		end
		single_page()
	end
	if opts.worker then
		update_worker_index()
	end
end

function next_page()
	if opts.double and valid_width then
		change_page(2)
	else
		change_page(1)
	end
end

function prev_page()
	if opts.double then
		change_page(-2)
	else
		change_page(-1)
	end
end

function next_single_page()
	change_page(1)
end

function prev_single_page()
	change_page(-1)
end

function first_page()
	index = 0
	change_page(0)
end

function last_page()
	if opts.double then
		index = length - 2
	else
		index = length - 1
	end
	change_page(0)
end

function set_keys()
	if opts.manga then
		mp.add_forced_key_binding("LEFT", "next-page", next_page)
		mp.add_forced_key_binding("RIGHT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+LEFT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+RIGHT", "prev-single-page", prev_single_page)
	else
		mp.add_forced_key_binding("RIGHT", "next-page", next_page)
		mp.add_forced_key_binding("LEFT", "prev-page", prev_page)
		mp.add_forced_key_binding("Shift+RIGHT", "next-single-page", next_single_page)
		mp.add_forced_key_binding("Shift+LEFT", "prev-single-page", prev_single_page)
	end
	mp.add_forced_key_binding("HOME", "first-page", first_page)
	mp.add_forced_key_binding("END", "last-page", last_page)
end

function startup_msg()
	if detect.image and not detect.err then
		mp.osd_message("Manga Reader Started")
	elseif detect.archive and detect.err then
		mp.osd_message("Archive type not supported")
	else
		mp.osd_message("Not an image")
	end
end

function remove_tmp_files()
	close_manga_reader()
	if names ~= nil then
		os.execute("rm "..names.." &>/dev/null")
	end
	if detect.archive and not detect.err then
		if utils.file_info(dir) then
			dir = escape_special_characters(dir)
			os.execute("rm -r "..dir.." &>/dev/null")
		end
	end
end

function remove_tmp_files_no_shutdown()
	if names ~= nil then
		os.execute("rm "..names.." &>/dev/null")
	end
	if detect.archive and not detect.err then
		if utils.file_info(dir) then
			dir = escape_special_characters(dir)
			os.execute("rm -r "..dir.." &>/dev/null")
		end
	end
end

function setup_workers(workers)
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "setup-worker", tostring(detect.archive), 
                    tostring(detect.p7zip), tostring(detect.rar), tostring(detect.tar),
                    tostring(detect.zip), tostring(i), root)
		i = i + 1
	end
end

function update_worker_bools()
	local i = 1
	while workers[i] do
		local name = strip_file_ext(workers[i])
		name = string.gsub(name, "-", "_")
		mp.commandv("script-message-to", name, "update-bools", tostring(opts.manga), tostring(opts.worker))
		i = i +1
	end
end

function toggle_double_page()
	if opts.double then
		mp.osd_message("Double Page Mode Off")
		opts.double = false
	else
		mp.osd_message("Double Page Mode On")
		opts.double = true
	end
	change_page(0)
end

function toggle_manga_mode()
	local name = mp.get_property("path")
	if opts.manga then
		mp.osd_message("Manga Mode Off")
		opts.manga = false
	else
		mp.osd_message("Manga Mode On")
		opts.manga = true
	end
	set_keys()
	remove_tmp_files_no_shutdown()
	update_worker_bools()
	names = nil
	change_page(0)
end

function toggle_worker()
	if opts.worker then
		opts.worker = false
		mp.osd_message("Stopping Workers")
	else
		opts.worker = true
		mp.osd_message("Starting Workers")
	end
	update_worker_bools()
end

function close_manga_reader()
	if detect.init then
		mp.remove_key_binding("next-page")
		mp.remove_key_binding("prev-page")
		mp.remove_key_binding("next-single-page")
		mp.remove_key_binding("prev-single-page")
		mp.remove_key_binding("first-page")
		mp.remove_key_binding("last-page")
	end
	if not detect.err and detect.image then
		mp.commandv("loadfile", init_arg, "replace")
	end
	opts.worker = false
	update_worker_bools()
end

function start_manga_reader()
	read_options(opts, "manga-reader")
	local home = io.popen("echo $HOME")
	io.input(home)
	local home_dir = io.read()
	io.close()
	local cfg_dir = ".config/mpv/scripts"
	local script_dir = utils.join_path(home_dir, cfg_dir)
	local scripts = utils.readdir(script_dir)
	local i = 1
	while scripts[i] do
		if string.find(scripts[i], "manga-worker", 0, true) then
			workers[i] = scripts[i]
		end
		i = i + 1
	end
	local path = mp.get_property("path")
	detect.archive = check_archive(path)
	root = get_root(path)
	if detect.archive then
		local type_found = check_archive_type()
		if not type_found then
			detect.err = true
			toggle_reader()
			return
		end
		dir = string.gsub(path, ".*|", "")
		dir = string.gsub(dir, "/.*", "")
		init_arg = string.gsub(root, ".*/", "") 
		init_arg = string.gsub(init_arg, "\\", "")
	else
		init_arg = root
		init_arg = string.gsub(init_arg, "\\", "")
	end
	local filelist = get_filelist(root)
	i = 0
	for filename in filelist:lines() do
		filename = escape_special_characters(filename)
		local dims = get_dims(filename)
		if dims ~= nil then
			filearray[i] = filename
			filedims[i] = dims
			i = i + 1
		end
	end
	length = i
	filelist:close()
	set_keys()
	if workers[1] then
		setup_workers(workers)
	end
	mp.set_property_bool("osc", false)
	mp.set_property_bool("idle", true)
	mp.add_key_binding("m", "toggle-manga-mode", toggle_manga_mode)
	mp.add_key_binding("d", "toggle-double-page", toggle_double_page)
	mp.add_key_binding("a", "toggle-worker", toggle_worker)
	index = 0
	change_page(0)
end

function toggle_reader()
	if detect.init then
		close_manga_reader()
		detect.init = false
		mp.osd_message("Closing Reader")
	else
		detect.image = check_image()
		if detect.image then
			detect.init = true
			start_manga_reader()
		end
		startup_msg()
	end
end

mp.register_event("shutdown", remove_tmp_files)
mp.add_key_binding("y", "toggle-manga-reader", toggle_reader)
