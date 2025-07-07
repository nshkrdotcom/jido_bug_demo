# 104: Migration Tooling Implementation

## Overview

This document provides comprehensive implementation details for automated migration tools that will help users transition from the separated jido/jido_signal architecture to the unified framework, including code analysis, transformation, and validation tools.

## Migration Tool Architecture

### 1. Core Migration Framework

```elixir
# lib/mix/tasks/jido/migrate.ex
defmodule Mix.Tasks.Jido.Migrate do
  @moduledoc """
  Automated migration tool for Jido 2.0 upgrade.
  
  Usage:
    mix jido.migrate [options]
    
  Options:
    --check          Analyze code without making changes
    --interactive    Prompt before each change
    --backup         Create backups (default: true)
    --parallel       Run migrations in parallel
    --verbose        Show detailed output
  """
  
  use Mix.Task
  
  alias Jido.Migration.{
    Analyzer,
    Transformer,
    Validator,
    Reporter,
    Backup
  }
  
  @impl Mix.Task
  def run(args) do
    Mix.Task.run("compile")
    
    opts = parse_args(args)
    
    with :ok <- validate_environment(),
         {:ok, backup_path} <- maybe_backup(opts),
         {:ok, analysis} <- analyze_codebase(opts),
         :ok <- confirm_changes(analysis, opts),
         {:ok, results} <- apply_migrations(analysis, opts),
         :ok <- validate_results(results, opts) do
      
      Reporter.generate_report(results, opts)
      Mix.shell().info("Migration completed successfully!")
      
    else
      {:error, reason} ->
        Mix.shell().error("Migration failed: #{inspect(reason)}")
        exit(1)
    end
  end
  
  defp validate_environment do
    cond do
      not Code.ensure_loaded?(Jido) ->
        {:error, "Jido is not loaded. Please add it to your dependencies."}
        
      Version.match?(jido_version(), "~> 1.0") ->
        :ok
        
      true ->
        {:error, "This migration tool is for Jido 1.x to 2.0 only"}
    end
  end
  
  defp analyze_codebase(opts) do
    Mix.shell().info("Analyzing codebase...")
    
    files = find_elixir_files()
    
    analysis = %{
      files: files,
      agents: Analyzer.find_agents(files),
      actions: Analyzer.find_actions(files),
      signals: Analyzer.find_signal_usage(files),
      deprecations: Analyzer.find_deprecations(files),
      type_issues: Analyzer.find_type_issues(files)
    }
    
    if opts[:check] do
      Reporter.print_analysis(analysis)
      exit(0)
    else
      {:ok, analysis}
    end
  end
  
  defp apply_migrations(analysis, opts) do
    Mix.shell().info("Applying migrations...")
    
    results = if opts[:parallel] do
      apply_parallel_migrations(analysis, opts)
    else
      apply_sequential_migrations(analysis, opts)
    end
    
    {:ok, results}
  end
end
```

### 2. Code Analyzer

```elixir
# lib/jido/migration/analyzer.ex
defmodule Jido.Migration.Analyzer do
  @moduledoc """
  Analyzes code to identify migration points.
  """
  
  @doc """
  Finds all agent modules that need migration.
  """
  def find_agents(files) do
    files
    |> Enum.flat_map(&analyze_file_for_agents/1)
    |> Enum.uniq()
  end
  
  defp analyze_file_for_agents(file) do
    ast = File.read!(file) |> Code.string_to_quoted!()
    
    {_, agents} = Macro.prewalk(ast, [], fn
      # Find use Jido.Agent
      {:use, _, [{:__aliases__, _, [:Jido, :Agent]} | _]} = node, acc ->
        module = extract_module_name(ast)
        {node, [{file, module, :polymorphic_struct} | acc]}
        
      # Find defstruct in agent modules
      {:defstruct, _, [fields]} = node, acc when is_list(fields) ->
        if agent_module?(ast) do
          {node, [{file, :defstruct_in_agent, fields} | acc]}
        else
          {node, acc}
        end
        
      node, acc ->
        {node, acc}
    end)
    
    agents
  end
  
  @doc """
  Finds signal usage that needs updating.
  """
  def find_signal_usage(files) do
    patterns = [
      # Field access patterns
      {~r/\.jido_dispatch/, :jido_dispatch_field},
      {~r/\.jido_meta/, :jido_meta_field},
      {~r/%\{jido_dispatch:/, :jido_dispatch_map},
      {~r/%\{jido_meta:/, :jido_meta_map},
      
      # Import patterns
      {~r/alias\s+Jido\.Signal/, :signal_alias},
      {~r/import\s+Jido\.Signal/, :signal_import},
      
      # Dependency patterns
      {~r/\{:jido_signal,/, :jido_signal_dep}
    ]
    
    files
    |> Enum.flat_map(fn file ->
      content = File.read!(file)
      
      Enum.flat_map(patterns, fn {pattern, type} ->
        Regex.scan(pattern, content, return: :index)
        |> Enum.map(fn [{start, length}] ->
          line = get_line_number(content, start)
          {file, line, type, get_context(content, start, length)}
        end)
      end)
    end)
  end
  
  @doc """
  Finds type issues related to polymorphic structs.
  """
  def find_type_issues(files) do
    files
    |> Enum.flat_map(&analyze_file_for_types/1)
  end
  
  defp analyze_file_for_types(file) do
    ast = File.read!(file) |> Code.string_to_quoted!()
    
    {_, issues} = Macro.prewalk(ast, [], fn
      # Pattern match on specific agent struct
      {:%, _, [{:__aliases__, _, module_parts}, _]} = node, acc ->
        module = Module.concat(module_parts)
        if agent_module?(module) do
          {node, [{file, :agent_struct_pattern, module} | acc]}
        else
          {node, acc}
        end
        
      # Struct update syntax
      {:%{}, _, [{:|, _, [struct_var, _]}]} = node, acc ->
        {node, [{file, :struct_update, struct_var} | acc]}
        
      node, acc ->
        {node, acc}
    end)
    
    issues
  end
  
  defp extract_module_name(ast) do
    case ast do
      {:defmodule, _, [{:__aliases__, _, parts} | _]} ->
        Module.concat(parts)
      _ ->
        nil
    end
  end
  
  defp agent_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__jido_agent__, 0)
  end
  
  defp agent_module?(_), do: false
end
```

### 3. Code Transformer

```elixir
# lib/jido/migration/transformer.ex
defmodule Jido.Migration.Transformer do
  @moduledoc """
  Transforms code to new patterns.
  """
  
  @doc """
  Transforms an agent module to use Instance.
  """
  def transform_agent_file(file_path, opts \\ []) do
    content = File.read!(file_path)
    ast = Code.string_to_quoted!(content)
    
    transformed_ast = transform_agent_ast(ast, opts)
    
    new_content = Macro.to_string(transformed_ast)
    |> format_code()
    
    if opts[:dry_run] do
      {:ok, new_content}
    else
      File.write!(file_path, new_content)
      {:ok, file_path}
    end
  end
  
  defp transform_agent_ast(ast, _opts) do
    Macro.prewalk(ast, fn
      # Remove defstruct from agents
      {:defstruct, meta, [_fields]} = node ->
        if in_agent_module?(node) do
          {:__block__, meta, []}  # Remove the node
        else
          node
        end
        
      # Transform struct patterns to Instance
      {:%, meta1, [{:__aliases__, meta2, module_parts}, {:%{}, meta3, fields}]} = node ->
        module = Module.concat(module_parts)
        if agent_module?(module) do
          # Transform to Instance pattern match
          {:%, meta1, [
            {:__aliases__, meta2, [:Jido, :Agent, :Instance]},
            {:%{}, meta3, [{:module, module} | transform_fields(fields)]}
          ]}
        else
          node
        end
        
      # Update field access
      {{:., meta, [struct_var, field]}, meta2, []} = node ->
        if field in [:jido_dispatch, :jido_meta] do
          new_field = case field do
            :jido_dispatch -> :dispatch
            :jido_meta -> :meta
          end
          {{:., meta, [struct_var, new_field]}, meta2, []}
        else
          node
        end
        
      node ->
        node
    end)
  end
  
  defp transform_fields(fields) do
    Enum.map(fields, fn
      {:jido_dispatch, value} -> {:dispatch, value}
      {:jido_meta, value} -> {:meta, value}
      field -> field
    end)
  end
  
  @doc """
  Updates mix.exs dependencies.
  """
  def update_mix_deps(mix_file \\ "mix.exs") do
    content = File.read!(mix_file)
    
    # Parse mix.exs
    ast = Code.string_to_quoted!(content)
    
    # Transform dependencies
    new_ast = Macro.prewalk(ast, fn
      # Remove jido_signal dependency
      {:jido_signal, _, _} ->
        {:__block__, [], []}
        
      # Update jido version
      {:jido, meta, ["~> 1.0" <> _]} ->
        {:jido, meta, ["~> 2.0"]}
        
      node ->
        node
    end)
    
    new_content = Macro.to_string(new_ast) |> format_code()
    
    File.write!(mix_file, new_content)
    {:ok, mix_file}
  end
  
  defp format_code(code) do
    case Code.format_string!(code) do
      formatted -> IO.iodata_to_binary(formatted)
    rescue
      _ -> code  # Return unformatted if formatting fails
    end
  end
end
```

### 4. Pattern-Based Transformations

```elixir
# lib/jido/migration/patterns.ex
defmodule Jido.Migration.Patterns do
  @moduledoc """
  Pattern-based code transformations.
  """
  
  @patterns [
    # Agent struct patterns
    %{
      name: :agent_struct_match,
      pattern: ~S"%MyAgent{",
      replacement: ~S"%Jido.Agent.Instance{module: MyAgent, ",
      description: "Update agent struct pattern matching"
    },
    
    # Signal field patterns
    %{
      name: :jido_dispatch_field,
      pattern: ~r/(\w+)\.jido_dispatch/,
      replacement: ~S"\1.dispatch",
      description: "Update jido_dispatch field access"
    },
    
    # Import patterns
    %{
      name: :remove_signal_import,
      pattern: ~r/^\s*import\s+Jido\.Signal\s*$/m,
      replacement: "",
      description: "Remove redundant signal import"
    }
  ]
  
  @doc """
  Apply all patterns to a file.
  """
  def apply_patterns(file_path, opts \\ []) do
    content = File.read!(file_path)
    
    results = Enum.reduce(@patterns, {content, []}, fn pattern, {text, changes} ->
      case apply_pattern(text, pattern, opts) do
        {:ok, new_text, occurrences} ->
          {new_text, [{pattern.name, occurrences} | changes]}
          
        :no_match ->
          {text, changes}
      end
    end)
    
    case results do
      {new_content, changes} when changes != [] ->
        if opts[:dry_run] do
          {:ok, new_content, Enum.reverse(changes)}
        else
          File.write!(file_path, new_content)
          {:ok, file_path, Enum.reverse(changes)}
        end
        
      {_, []} ->
        :no_changes
    end
  end
  
  defp apply_pattern(text, %{pattern: pattern, replacement: replacement}, _opts) do
    if Regex.match?(pattern, text) do
      occurrences = length(Regex.scan(pattern, text))
      new_text = Regex.replace(pattern, text, replacement)
      {:ok, new_text, occurrences}
    else
      :no_match
    end
  end
end
```

### 5. Interactive Migration Mode

```elixir
# lib/jido/migration/interactive.ex
defmodule Jido.Migration.Interactive do
  @moduledoc """
  Interactive migration with user confirmation.
  """
  
  def run(analysis, opts) do
    IO.puts("\n🔄 Jido Migration Tool - Interactive Mode\n")
    
    # Group changes by type
    changes = group_changes(analysis)
    
    # Process each group
    Enum.reduce(changes, %{applied: [], skipped: []}, fn {type, items}, acc ->
      IO.puts("\n📁 #{humanize(type)} (#{length(items)} items)")
      IO.puts(String.duplicate("-", 50))
      
      Enum.reduce(items, acc, fn item, inner_acc ->
        case prompt_for_change(type, item) do
          :yes ->
            apply_change(type, item)
            %{inner_acc | applied: [item | inner_acc.applied]}
            
          :no ->
            %{inner_acc | skipped: [item | inner_acc.skipped]}
            
          :all ->
            # Apply all remaining changes of this type
            remaining = items -- inner_acc.applied -- inner_acc.skipped
            Enum.each(remaining, &apply_change(type, &1))
            %{inner_acc | applied: inner_acc.applied ++ remaining}
        end
      end)
    end)
  end
  
  defp prompt_for_change(type, item) do
    IO.puts("\n#{format_change(type, item)}")
    
    response = IO.gets("\nApply this change? [y/n/a/q]: ")
    |> String.trim()
    |> String.downcase()
    
    case response do
      "y" -> :yes
      "n" -> :no
      "a" -> :all
      "q" -> exit(:normal)
      _ -> prompt_for_change(type, item)  # Ask again
    end
  end
  
  defp format_change(:agent_struct, {file, line, module}) do
    """
    📍 #{file}:#{line}
    Change: Convert #{inspect(module)} to use Jido.Agent.Instance
    
    Before:
      %#{inspect(module)}{id: id, state: state}
      
    After:
      %Jido.Agent.Instance{module: #{inspect(module)}, id: id, state: state}
    """
  end
  
  defp format_change(:signal_field, {file, line, field, context}) do
    """
    📍 #{file}:#{line}
    Change: Update signal field #{field}
    
    Context:
      #{context}
    """
  end
end
```

### 6. Validation Tool

```elixir
# lib/jido/migration/validator.ex
defmodule Jido.Migration.Validator do
  @moduledoc """
  Validates migrated code for correctness.
  """
  
  def validate_migration(opts \\ []) do
    validators = [
      &validate_no_polymorphic_structs/1,
      &validate_signal_fields/1,
      &validate_dependencies/1,
      &validate_type_specs/1,
      &validate_dialyzer/1
    ]
    
    results = Enum.map(validators, fn validator ->
      {validator, validator.(opts)}
    end)
    
    failed = Enum.filter(results, fn {_, result} ->
      match?({:error, _}, result)
    end)
    
    if failed == [] do
      {:ok, "All validations passed"}
    else
      {:error, format_validation_errors(failed)}
    end
  end
  
  defp validate_no_polymorphic_structs(_opts) do
    # Find any remaining polymorphic struct usage
    files = find_elixir_files()
    
    issues = Enum.flat_map(files, fn file ->
      ast = File.read!(file) |> Code.string_to_quoted!()
      find_polymorphic_patterns(ast, file)
    end)
    
    if issues == [] do
      {:ok, "No polymorphic structs found"}
    else
      {:error, "Found #{length(issues)} polymorphic struct patterns", issues}
    end
  end
  
  defp validate_signal_fields(_opts) do
    # Check for old signal field names
    patterns = [
      {~r/jido_dispatch/, "jido_dispatch field"},
      {~r/jido_meta/, "jido_meta field"}
    ]
    
    issues = find_pattern_matches(patterns)
    
    if issues == [] do
      {:ok, "No old signal fields found"}
    else
      {:error, "Found old signal field references", issues}
    end
  end
  
  defp validate_dialyzer(opts) do
    if opts[:skip_dialyzer] do
      {:ok, "Dialyzer check skipped"}
    else
      Mix.shell().info("Running dialyzer...")
      
      case System.cmd("mix", ["dialyzer"], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, "Dialyzer passed"}
          
        {output, _} ->
          warnings = parse_dialyzer_output(output)
          {:error, "Dialyzer warnings found", warnings}
      end
    end
  end
end
```

### 7. Migration Report Generator

```elixir
# lib/jido/migration/reporter.ex
defmodule Jido.Migration.Reporter do
  @moduledoc """
  Generates migration reports.
  """
  
  def generate_report(results, opts) do
    report = build_report(results)
    
    # Write to file
    filename = "migration_report_#{timestamp()}.md"
    File.write!(filename, report)
    
    # Print summary
    if opts[:verbose] do
      IO.puts(report)
    else
      print_summary(results)
    end
    
    IO.puts("\n📄 Full report saved to: #{filename}")
  end
  
  defp build_report(results) do
    """
    # Jido Migration Report
    
    Generated: #{DateTime.utc_now()}
    
    ## Summary
    
    - Files analyzed: #{results.files_count}
    - Files modified: #{results.modified_count}
    - Agents migrated: #{results.agents_count}
    - Signal usages updated: #{results.signals_count}
    - Type issues fixed: #{results.types_count}
    
    ## Detailed Changes
    
    ### Agent Migrations
    
    #{format_agent_changes(results.agent_changes)}
    
    ### Signal Field Updates
    
    #{format_signal_changes(results.signal_changes)}
    
    ### Type System Updates
    
    #{format_type_changes(results.type_changes)}
    
    ## Validation Results
    
    #{format_validation_results(results.validation)}
    
    ## Next Steps
    
    1. Review the changes in your version control system
    2. Run your test suite: `mix test`
    3. Check dialyzer: `mix dialyzer`
    4. Update your documentation
    5. Deploy with confidence!
    
    ## Rollback
    
    If you need to rollback:
    ```bash
    git checkout #{results.backup_ref}
    ```
    """
  end
  
  defp format_agent_changes(changes) do
    changes
    |> Enum.map(fn {file, module} ->
      "- `#{file}`: Migrated `#{inspect(module)}` to use `Jido.Agent.Instance`"
    end)
    |> Enum.join("\n")
  end
end
```

### 8. Rollback Support

```elixir
# lib/jido/migration/rollback.ex
defmodule Jido.Migration.Rollback do
  @moduledoc """
  Rollback support for migrations.
  """
  
  def create_rollback_point(opts) do
    # Git-based rollback
    if git_available?() do
      # Create a backup branch
      branch_name = "jido-migration-backup-#{timestamp()}"
      System.cmd("git", ["checkout", "-b", branch_name])
      System.cmd("git", ["add", "."])
      System.cmd("git", ["commit", "-m", "Backup before Jido migration"])
      
      {:ok, branch_name}
    else
      # File-based backup
      backup_dir = ".jido_migration_backup_#{timestamp()}"
      File.mkdir_p!(backup_dir)
      
      # Copy all Elixir files
      copy_files_to_backup(backup_dir)
      
      {:ok, backup_dir}
    end
  end
  
  def rollback(backup_ref) do
    cond do
      branch_exists?(backup_ref) ->
        System.cmd("git", ["checkout", backup_ref])
        {:ok, "Rolled back to branch: #{backup_ref}"}
        
      File.dir?(backup_ref) ->
        restore_from_backup(backup_ref)
        {:ok, "Restored from backup: #{backup_ref}"}
        
      true ->
        {:error, "Backup not found: #{backup_ref}"}
    end
  end
end
```

### 9. CI/CD Integration

```yaml
# .github/workflows/jido_migration.yml
name: Jido Migration Check

on:
  pull_request:
    branches: [ main ]

jobs:
  migration-check:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: '1.14'
        otp-version: '25.0'
        
    - name: Install dependencies
      run: mix deps.get
      
    - name: Run migration check
      run: mix jido.migrate --check
      
    - name: Upload report
      if: always()
      uses: actions/upload-artifact@v3
      with:
        name: migration-report
        path: migration_report_*.md
```

### 10. Common Migration Scenarios

```elixir
# lib/jido/migration/scenarios.ex
defmodule Jido.Migration.Scenarios do
  @moduledoc """
  Handles common migration scenarios.
  """
  
  @doc """
  Migrates a Phoenix application using Jido.
  """
  def migrate_phoenix_app(app_path) do
    # Update router
    update_phoenix_router(app_path)
    
    # Update channels
    update_phoenix_channels(app_path)
    
    # Update contexts
    update_phoenix_contexts(app_path)
  end
  
  @doc """
  Migrates a distributed Jido system.
  """
  def migrate_distributed_system(nodes) do
    # Coordinate migration across nodes
    coordinator = start_migration_coordinator()
    
    # Phase 1: Prepare all nodes
    prepare_nodes(nodes, coordinator)
    
    # Phase 2: Apply migrations
    apply_distributed_migrations(nodes, coordinator)
    
    # Phase 3: Verify system health
    verify_distributed_system(nodes)
  end
  
  @doc """
  Migrates with zero downtime.
  """
  def zero_downtime_migration(opts) do
    # Step 1: Deploy compatibility layer
    deploy_compatibility_layer()
    
    # Step 2: Gradual rollout
    rollout_strategy = opts[:strategy] || :canary
    
    case rollout_strategy do
      :canary -> canary_deployment(opts)
      :blue_green -> blue_green_deployment(opts)
      :rolling -> rolling_deployment(opts)
    end
  end
end
```

This comprehensive migration tooling provides automated, safe, and reversible migration from the separated architecture to the unified Jido framework, with support for various deployment scenarios and validation at every step.