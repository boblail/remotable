module Remotable
  module Nosync

    def self.included(base)
      base.include InstanceMethods
    end

    def self.extended(base)
      base.extend ClassMethods
    end

    module InstanceMethods

      def nosync!
        self.nosync = true
      end

      def reset_nosync!
        remove_instance_variable(:@nosync) if instance_variable_defined?(:@nosync)
      end

      def nosync(new_value=true)
        old_value = _nosync
        self.nosync = new_value
        yield
      ensure
        self.nosync = old_value
      end

      def nosync=(val)
        @nosync = val
      end

      def nosync_value?
        !_nosync.nil?
      end

      def nosync?
        !!_nosync
      end

    private

      def _nosync
        @nosync if instance_variable_defined?(:@nosync)
      end

    end

    module ClassMethods
      include InstanceMethods

      def unsafe_nosync!
        nosync!
        @_unsafe_nosync = true
      end

      def reset_nosync!
        self.nosync = nil
        remove_instance_variable :@_unsafe_nosync if instance_variable_defined? :@_unsafe_nosync
      end

      def nosync=(val)
        self._nosync = val
      end

    private

      def _nosync
        return Thread.current.thread_variable_get "remotable.nosync.#{self.object_id}" if nosync_defined_on?(Thread.current)
        @_unsafe_nosync if instance_variable_defined?(:@_unsafe_nosync)
      end

      def _nosync=(value)
        Thread.current.thread_variable_set "remotable.nosync.#{self.object_id}", value
        Thread.current.thread_variable_set "remotable.nosync.#{self.object_id}.defined", true
      end

      def nosync_defined_on?(thread)
        !!thread.thread_variable_get("remotable.nosync.#{self.object_id}.defined")
      end

    end

  end
end
