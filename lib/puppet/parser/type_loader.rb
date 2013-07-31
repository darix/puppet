require 'puppet/node/environment'

class Puppet::Parser::TypeLoader
  include Puppet::Node::Environment::Helper

  # Helper class that makes sure we don't try to import the same file
  # more than once from either the same thread or different threads.
  class Helper
    include MonitorMixin
    def initialize
      super
      # These hashes are indexed by filename
      @state = {} # :doing or :done
      @thread = {} # if :doing, thread that's doing the parsing
      @cond_var = {} # if :doing, condition var that will be signaled when done.
    end

    # Execute the supplied block exactly once per file, no matter how
    # many threads have asked for it to run.  If another thread is
    # already executing it, wait for it to finish.  If this thread is
    # already executing it, return immediately without executing the
    # block.
    #
    # Note: the reason for returning immediately if this thread is
    # already executing the block is to handle the case of a circular
    # import--when this happens, we attempt to recursively re-parse a
    # file that we are already in the process of parsing.  To prevent
    # an infinite regress we need to simply do nothing when the
    # recursive import is attempted.
    def do_once(file)
      need_to_execute = synchronize do
        case @state[file]
        when :doing
          if @thread[file] != Thread.current
            @cond_var[file].wait
          end
          false
        when :done
          false
        else
          @state[file] = :doing
          @thread[file] = Thread.current
          @cond_var[file] = new_cond
          true
        end
      end
      if need_to_execute
        begin
          yield
        ensure
          synchronize do
            @state[file] = :done
            @thread.delete(file)
            @cond_var.delete(file).broadcast
          end
        end
      end
    end
  end

  # Import manifest files that match a given file glob pattern.
  #
  # @param pattern [String] the file glob to apply when determining which files
  #   to load
  # @param dir [String] base directory to use when the file is not
  #   found in a module
  # @api private
  def import(pattern, dir)
    return if Puppet[:ignoreimport]

    modname, files = Puppet::Parser::Files.find_manifests_in_modules(pattern, environment)
    if files.empty?
      abspat = File.expand_path(pattern, dir)
      file_pattern = abspat + (File.extname(abspat).empty? ? '{.pp,.rb}' : '' )

      files = Dir.glob(file_pattern).uniq.reject { |f| FileTest.directory?(f) }
      modname = nil

      if files.empty?
        raise_no_files_found(pattern)
      end
	end
    load_files(modname, files)
  end

  def known_resource_types
    environment.known_resource_types
  end

  def initialize(env)
    self.environment = env
    @loading_helper = Helper.new
  end

  def load_until(namespaces, name)
    return nil if name == "" # special-case main.
    name2files(namespaces, name).each do |filename|
      modname = begin
        import(filename)
      rescue Puppet::ImportError => detail
        # We couldn't load the item
        # I'm not convienced we should just drop these errors, but this
        # preserves existing behaviours.
        nil
      end
      if result = yield(filename)
        Puppet.debug "Automatically imported #{name} from #{filename} into #{environment}"
        result.module_name = modname if modname and result.respond_to?(:module_name=)
        return result
      end
    end
    nil
  end
  def import_from_modules(pattern)
    modname, files = Puppet::Parser::Files.find_manifests_in_modules(pattern, environment)
    if files.empty?
      raise_no_files_found(pattern)
    end

    load_files(modname, files)
  end

  def raise_no_files_found(pattern)
    raise Puppet::ImportError, "No file(s) found for import of '#{pattern}'"
  end

  def load_files(modname, files)
    loaded_asts = []
   files.each do |file|
      @loading_helper.do_once(file) do
        loaded_asts << parse_file(file)
      end
    end

    loaded_asts.collect do |ast|
      known_resource_types.import_ast(ast, modname)
    end.flatten
  end

  def name2files(namespaces, name)
    return [name.sub(/^::/, '').gsub("::", File::SEPARATOR)] if name =~ /^::/

    result = namespaces.inject([]) do |names_to_try, namespace|
      fullname = (namespace + "::#{name}").sub(/^::/, '')

      # Try to load the module init file if we're a qualified name
      names_to_try << fullname.split("::")[0] if fullname.include?("::")

      # Then the fully qualified name
      names_to_try << fullname
    end

    # Otherwise try to load the bare name on its own.  This
    # is appropriate if the class we're looking for is in a
    # module that's different from our namespace.
    result << name
    result.uniq.collect { |f| f.gsub("::", File::SEPARATOR) }
  end

  def parse_file(file)
    Puppet.debug("importing '#{file}' in environment #{environment}")
    parser = Puppet::Parser::Parser.new(environment)
    parser.file = file
    parser.parse
  end
end
