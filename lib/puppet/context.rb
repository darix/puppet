# Puppet::Context is a system for tracking services and contextual information
# that puppet needs to be able to run. Values are "bound" in a context when it is created
# and cannot be changed; however a child context can be created, using
# {#override}, that provides a different value.
#
# @api private
class Puppet::Context
  require 'puppet/context/trusted_information'

  class UndefinedBindingError < Puppet::Error; end
  class StackUnderflow < Puppet::Error; end

  # @api private
  def initialize(initial_bindings)
    @stack = []
    @table = initial_bindings
    @description = "root"
  end

  # @api private
  def push(overrides, description = "")
    @stack.push([@table, @description])
    @table = @table.merge(overrides || {})
    @description = description
  end

  # @api private
  def pop
    if @stack.empty?
      raise(StackUnderflow, "Attempted to pop, but already at root of the context stack.")
    else
      (@table, @description) = @stack.pop
    end
  end

  # @api private
  def lookup(name, &block)
    if @table.include?(name)
      @table[name]
    elsif block
      block.call
    else
      raise UndefinedBindingError, "no '#{name}' in #{@table.inspect} at top of #{@stack.inspect}"
    end
  end

  # @api private
  def override(bindings, description = "", &block)
    push(bindings, description)

    yield
  ensure
    pop
  end
end
