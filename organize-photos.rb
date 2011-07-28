#!/usr/bin/ruby
#
# usage: ruby organize-photos.rb dst-directory-format path [path ...]
#
# moves photos at paths to dst-diectory formated through strftime
# with date and time of each photo
#
# example for a dry run:
#	find /backup1/tmp -type f -print0 | sort -z |\
#	xargs -0 ruby ~/organize-photos/organize-photos.rb \
#	-n /backup1/Archive/Photo/Photo%y/%y%m 2>&1 |\
#	tee organize-photos.`date +%Y%m%d`.log
#
# Copyright (C) 2011 by zunda <zunda at freeshell.org>
#
# Permission is granted for use, copying, modification, distribution,
# and distribution of modified versions of this work as long as the
# above copyright notice is included.
#

require 'exif'	# requires libexif-ruby package
require 'fileutils'
require 'optparse'

class Dir
	def Dir.paths(dirname)
		r = Array.new
		Dir.foreach(dirname) do |entry|
			next if '.' == entry or '..' == entry
			path = File.join(dirname, entry)
			unless File.directory?(path)
				r << path
			else
				r += Dir.paths(path)
			end
		end
		return r
	end
end

class Image
	DateTag = 'Date and Time (original)'	# in EXIF
	attr_reader :time

	def initialize(path)
		@path = path
		basename = File.basename(@path)
		@time = nil

		ts = Array.new

		# Try to obtain timestamp from EXIF
		begin
			x = Exif.new(path)[DateTag]
			ts << x.scan(/\d+/) if x
		rescue Exif::NotExifFormat
		end
		# them from filename with format yyyymmdd_hhmmss
		a = basename.scan(/(\d{4,4})(\d\d)(\d\d).*(\d\d)(\d\d)(\d\d)/)
		ts << a[0] if a and 1 == a.size
		# then from filename with format yyyy-mm-dd-hh-mm-ss
		a = basename.scan(/\d+/)
		ts << a[0..5] if a and 6 <= a.size
		# Try to parse time from the candidates
		ts.each do |timeary|
			begin
				@time = Time.local(*timeary)
			rescue ArgumentError
				next
			end
			break
		end
		# or use mtime
		unless @time
			@time = File.mtime(path)
		end
	end
end

class Conf
	attr_accessor :dry_run
	attr_accessor :moving
	attr_accessor :dst_format
	attr_accessor :quiet
	def initialize
		@dry_run = false
		@moving = false
		@quiet = false
		@dst_format = '/backup1/Archive/Photo/Photo%y/%y%m'
	end
end

conf = Conf.new
opt = OptionParser.new
opt.banner = "usage: #{opt.program_name} [options] file file..."
opt.on('-n', 'makes a dry run'){conf.dry_run = true}
opt.on('-m', 'moves the files instead of copying'){conf.moving = true}
opt.on('-d', "specifies format of destination, default: #{conf.dst_format}"){|x| conf.dst_format = x}
opt.on('-q', "supresses error messages"){conf.quiet = true}
opt.parse!(ARGV)

error = false
ARGV.each do |srcpath|
	begin
		# Parse EXIF and check timestamp
		image = Image.new(srcpath)
		unless image.time
			raise "does not have timestamp"
		end

		# Create destination
		srcname = File.basename(srcpath)
		dstdir = image.time.strftime(conf.dst_format)
		dstpath = File.join(dstdir, srcname)
		FileUtils.mkdir_p(dstdir)

		# Check similar file in destination
		if File.identical?(srcpath, dstpath)
			raise "is already in #{dstdir}"
		end
		if Dir.paths(dstdir).map{|p| File.basename(p).downcase}.include?(srcname.downcase)
			raise "has similar file below #{dstdir}"
		end

		# Move or copy the file
		unless conf.moving
			unless conf.dry_run
				FileUtils.cp(srcpath, dstpath, {:preserve => true})
				$stderr.puts "#{srcpath}\tcopied to #{dstpath}"
			else
				$stderr.puts "#{srcpath}\tpretending to copy to #{dstpath}"
			end
		else
			unless conf.dry_run
				FileUtils.mv(srcpath, dstpath)
				$stderr.puts "#{srcpath}\tmoved to #{dstpath}"
			else
				$stderr.puts "#{srcpath}\tpretending to move to #{dstpath}"
			end
		end

	rescue => evar
		$stderr.puts "#{srcpath}\t#{$!}" unless conf.quiet
		error = true
	end
end

exit 1 if error
