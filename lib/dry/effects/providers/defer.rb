# frozen_string_literal: true

require 'concurrent/promise'
require 'dry/effects/provider'

module Dry
  module Effects
    module Providers
      class Defer < Provider[:defer]
        include Dry::Equalizer(:executor)

        option :executor, default: -> { :io }

        attr_reader :later_calls

        attr_reader :stack

        def defer(block, executor)
          stack = self.stack.dup
          at = Undefined.default(executor, self.executor)
          ::Concurrent::Promise.execute(executor: at) do
            Handler.spawn_fiber(stack, &block)
          end
        end

        def later(block, executor)
          if @later_calls.frozen?
            Instructions.Raise(Errors::EffectRejected.new(<<~MSG))
              .later calls are not allowed, they would processed
              by another stack. Add another defer handler to the current stack
            MSG
          else
            at = Undefined.default(executor, self.executor)
            stack = self.stack.dup
            @later_calls << ::Concurrent::Promise.new(executor: at) do
              Handler.spawn_fiber(stack, &block)
            end
            nil
          end
        end

        def wait(promises)
          if promises.is_a?(::Array)
            ::Concurrent::Promise.zip(*promises).value!
          else
            promises.value!
          end
        end

        def call(stack, executor: Undefined)
          unless Undefined.equal?(executor)
            @executor = executor
          end

          @stack = stack
          @later_calls = []
          super(stack)
        ensure
          later_calls.each(&:execute)
        end

        def dup
          if defined? @later_calls
            super.tap { |p| p.instance_exec { @later_calls = EMPTY_ARRAY } }
          else
            super
          end
        end
      end
    end
  end
end
