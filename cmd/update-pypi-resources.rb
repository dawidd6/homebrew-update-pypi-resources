require "net/http"
require "cli/parser"

module Homebrew
  module_function

  def update_pypi_resources_args
    Homebrew::CLI::Parser.new do
      usage_banner <<~EOS
        `update-pypi-resources` [<options>] <formula>

        Checks for latest releases of python dependencies
        specified as resources pulled from pypi.org
        and writes updates back to formula.
      EOS
      switch "-n", "--dry-run",
             description: "Just print updated resources."
      switch "-v", "--verbose",
             description: "Be more specific."
      max_named 1
      min_named 1
    end
  end

  def name_and_version_from_url(url)
    regex = %r{https://files.pythonhosted.org/packages/.+/.+/.+/(.+)-([\d.]+)(.*)?\.(tar|zip)}
    match = url&.match(regex)
    if match
      name = match[1]
      version = match[2] + match[3]
      [name, version]
    end
  end

  def latest_url_and_checksum(name)
    uri = URI("https://pypi.org/pypi/#{name}/json")
    json = curl(uri)
    hash = JSON.parse(json)
    hash["urls"]&.reverse_each do |info|
      next unless info["packagetype"] == "sdist"

      return [info["url"], info["digests"]["sha256"]]
    end
  end

  def curl(uri)
    r = Net::HTTP.get_response(uri)
    if r.code == "301"
      uri = URI.parse(r.header["location"])
      curl(uri)
    else
      r.body
    end
  end

  def update_pypi_resources
    update_pypi_resources_args.parse

    opoo "writing updates back to formula" unless args.dry_run?

    formula = args.resolved_formulae.last
    formula&.resources&.each do |resource|
      next if resource.name == "homebrew-virtualenv"

      ohai resource.name

      name, version = name_and_version_from_url(resource.url)
      if !name || !version
        puts "can't parse name or version from url", resource.url if args.verbose?
        next
      end

      url, checksum = latest_url_and_checksum(name)
      if !url || !checksum
        puts "can't find latest url or checksum" if args.verbose?
        next
      end

      name, version_latest = name_and_version_from_url(url)
      if !name || !version
        puts "can't parse name or version from latest url", url if args.verbose?
        next
      end

      if version == version_latest
        puts "already up-to-date" if args.verbose?
        next
      end

      puts "#{version} -> #{version_latest}"

      next if args.dry_run?

      content = File.read(formula.path)
      content.gsub!(/#{resource.url}/, url)
      content.gsub!(/#{resource.checksum}/, checksum)
      File.open(formula.path, "w") { |file| file.write(content) }
    end
  end
end
