if Amrita.Elixir.Version.less_than_or_equal?([0, 9, 3]) do
  defmodule Amrita.Formatter.Pretty do
    defexception Amrita.VersionError, message: ""  do
    end

    def suite_started(_) do
      raise Amrita.VersionError, message: "Pretty formatter is not supported for <= 0.9.3"
    end
  end
else
  defmodule Amrita.Formatter.Pretty do
      @behaviour ExUnit.Formatter
      @timeout 30_000
      use GenServer.Behaviour

      import ExUnit.Formatter, only: [format_time: 2, format_test_failure: 4, format_test_case_failure: 4]

      defrecord Config, tests_counter: 0, invalid_counter: 0, pending_counter: 0,
                        test_failures: [], case_failures: [], pending_failures: []

      ## Behaviour

      def suite_started(_) do
        { :ok, pid } = :gen_server.start_link(__MODULE__, [], [])
        pid
      end

      def suite_finished(id, run_us, load_us) do
        :gen_server.call(id, { :suite_finished, run_us, load_us }, @timeout)
      end

      def case_started(id, test_case) do
        :gen_server.cast(id, { :case_started, test_case })
      end

      def case_finished(id, test_case) do
        :gen_server.cast(id, { :case_finished, test_case })
      end

      def test_started(id, test) do
        :gen_server.cast(id, { :test_started, test })
      end

      def test_finished(id, test) do
        :gen_server.cast(id, { :test_finished, test })
      end

      ## Callbacks

      def init(_) do
        { :ok, Config[] }
      end

      def handle_call({ :suite_finished, run_us, load_us }, _from, config) do
        print_suite(config.tests_counter, config.invalid_counter, config.pending_counter,
                    config.test_failures, config.case_failures, config.pending_failures, run_us, load_us)
        { :stop, :normal, length(config.test_failures), config }
      end

      def handle_call(reqest, from, config) do
        super(reqest, from, config)
      end

      def handle_cast({ :test_started, ExUnit.Test[] = test }, config) do
        IO.write("  * #{trace_test_name test}")
        { :noreply, config }
      end

      def handle_cast({ :test_finished, ExUnit.Test[failure: nil] = test }, config) do
        IO.puts success("\r  * #{trace_test_name test}")
        { :noreply, config.update_tests_counter(&1 + 1) }
      end

      def handle_cast({ :test_finished, ExUnit.Test[failure: { :invalid, _ }] = test }, config) do
        IO.puts invalid("\r  * #{trace_test_name test}")
        { :noreply, config.update_tests_counter(&1 + 1).update_invalid_counter(&1 + 1) }
      end

      def handle_cast({ :test_finished, test }, config) do
        ExUnit.Test[case: _test_case, name: _test, failure: { _, reason, _ }] = test
        exception_type = reason.__record__(:name)

        if exception_type == Elixir.Amrita.FactPending do
          IO.puts invalid("\r  * #{trace_test_name test}")
          { :noreply, config.update_pending_counter(&1 + 1).
          update_pending_failures([test|&1]) }
        else
          IO.puts failure("\r  * #{trace_test_name test}")
        { :noreply, config.update_tests_counter(&1 + 1).update_test_failures([test|&1]) }
        end
      end

      def handle_cast({ :case_started, ExUnit.TestCase[name: name] }, config) do
        IO.puts("\n#{name}")
        { :noreply, config }
      end

      def handle_cast({ :case_finished, test_case }, config) do
        if test_case.failure do
          { :noreply, config.update_case_failures([test_case|&1]) }
        else
          { :noreply, config }
        end
      end

      def handle_cast(request, config) do
        super(request, config)
      end

      defp trace_test_name(ExUnit.Test[name: name]) do
        case atom_to_binary(name) do
          "test_" <> rest -> rest
          "test " <> rest -> rest
        end
      end

      defp print_suite(counter, 0, num_pending, [], [], pending_failures, run_us, load_us) do
        IO.write "\n\nPending:\n\n"
        Enum.reduce Enum.reverse(pending_failures), 0, print_test_pending(&1, &2, File.cwd!)

        IO.puts format_time(run_us, load_us)
        IO.write success("#{counter} facts, ")
        if num_pending > 0 do
          IO.write success("#{num_pending} pending, ")
        end
        IO.write success "0 failures"
        IO.write "\n"
      end

      defp print_suite(counter, num_invalids, num_pending, test_failures, case_failures, pending_failures, run_us, load_us) do
        IO.write "\n\n"

        if num_pending > 0 do
          IO.write "Pending:\n\n"
          Enum.reduce Enum.reverse(pending_failures), 0, print_test_pending(&1, &2, File.cwd!)
        end

        IO.write "Failures:\n\n"
        num_fails = Enum.reduce Enum.reverse(test_failures), 0, print_test_failure(&1, &2, File.cwd!)
        Enum.reduce Enum.reverse(case_failures), num_fails, print_test_case_failure(&1, &2, File.cwd!)

        IO.puts format_time(run_us, load_us)
        message = "#{counter} facts"

        if num_invalids > 0 do
          message = message <>  ", #{num_invalids} invalid"
        end
        if num_pending > 0 do
          message = message <>  ", #{num_pending} pending"
        end

        message = message <> ", #{num_fails} failures"

        cond do
          num_fails > 0    -> IO.puts failure(message)
          num_invalids > 0 -> IO.puts invalid(message)
          true             -> IO.puts success(message)
        end
      end

      defp print_test_pending(test, acc, cwd) do
        IO.puts Amrita.Formatter.Format.format_test_pending(test, acc + 1, cwd, function(pending_formatter/2))
        acc + 1
      end

      defp print_test_failure(test, acc, cwd) do
        IO.puts format_test_failure(test, acc + 1, cwd, function(formatter/2))
        acc + 1
      end

      defp print_test_case_failure(test_case, acc, cwd) do
        IO.puts format_test_case_failure(test_case, acc + 1, cwd, function(formatter/2))
        acc + 1
      end

      # Color styles

      defp colorize(escape, string) do
        IO.ANSI.escape_fragment("%{#{escape}}") <> string <> IO.ANSI.escape_fragment("%{reset}")
      end

      defp success(msg) do
        colorize("green", msg)
      end

      defp invalid(msg) do
        colorize("yellow", msg)
      end

      defp failure(msg) do
        colorize("red", msg)
      end

      defp pending_formatter(:error_info, msg),    do: colorize("yellow", msg)
      defp pending_formatter(:location_info, msg), do: colorize("cyan", msg)
      defp pending_formatter(_,  msg),             do: msg

      defp formatter(:error_info, msg),    do: colorize("red", msg)
      defp formatter(:location_info, msg), do: colorize("cyan", msg)
      defp formatter(_,  msg),             do: msg

  end
end