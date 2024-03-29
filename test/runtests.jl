using Aqua
using Dates: Hour
using MockTableGenerators: MockTableGenerators, TableGenerator, collect_tables,
                           generate_tables, range
using StableRNGs
using Tables
using Test
using UUIDs: uuid4

@testset "MockTableGenerators" begin
    @testset "Aqua" begin
        Aqua.test_all(MockTableGenerators)
    end

    @testset "TableGenerator" begin
        @testset "dependencies" begin
            struct DemoGenerator <: TableGenerator
                num::Int
            end

            MockTableGenerators.table_key(g::DemoGenerator) = :demo
            MockTableGenerators.num_rows(rng, g::DemoGenerator) = g.num

            function MockTableGenerators.emit!(rng, g::DemoGenerator, deps)
                depends_on = haskey(deps, :demo) ? deps[:demo].id : nothing
                row = (; id=uuid4(rng), depends_on)
                return row
            end

            dag = DemoGenerator(2) => [DemoGenerator(1)]
            results = collect(MockTableGenerators.generate(StableRNG(1), dag))
            @test results == collect(MockTableGenerators.generate(StableRNG(1), dag))
            # test abstractvector method for _generate
            @test results == collect(MockTableGenerators.generate(StableRNG(1), [dag]))
            @test results != collect(MockTableGenerators.generate(dag))

            table_names = first.(results)
            rows = last.(results)

            @test length(rows) == 4
            @test all(==(:demo), table_names)
            @test rows[1].depends_on == nothing
            @test rows[2].depends_on == rows[1].id
            @test rows[3].depends_on == nothing
            @test rows[4].depends_on == rows[3].id

            nested_dags = (
                DemoGenerator(1) => DemoGenerator(1) => DemoGenerator(1),
                DemoGenerator(1) => DemoGenerator(1) => [DemoGenerator(1)],
                DemoGenerator(1) => [DemoGenerator(1) => DemoGenerator(1)],
                DemoGenerator(1) => [DemoGenerator(1) => [DemoGenerator(1)]],
                DemoGenerator(1) => (DemoGenerator(1) => DemoGenerator(1),),  # tuple
                Dict(DemoGenerator(1) => Dict(DemoGenerator(1) => DemoGenerator(1))), # dict
            )

            for dag in nested_dags
                results = collect(MockTableGenerators.generate(dag))
                rows = last.(results)
                @test rows[1].depends_on == nothing
                @test rows[2].depends_on == rows[1].id
                @test rows[3].depends_on == rows[2].id
            end
        end

        @testset "variable rows" begin
            struct VariableGenerator <: TableGenerator
                num::AbstractRange{Int}
            end

            MockTableGenerators.table_key(g::VariableGenerator) = :var
            MockTableGenerators.num_rows(rng, g::VariableGenerator) = rand(rng, g.num)
            MockTableGenerators.emit!(rng, g::VariableGenerator, deps) = (; id=uuid4(rng))

            dag = VariableGenerator(1:2)
            rows_a = last.(MockTableGenerators.generate(StableRNG(1), dag))
            @test rows_a == last.(MockTableGenerators.generate(StableRNG(1), dag))
            @test 1 <= length(rows_a) <= 2
        end

        @testset "stateful" begin
            struct StatefulGenerator <: TableGenerator
                num::AbstractRange{Int}
            end

            function MockTableGenerators.visit!(rng, g::StatefulGenerator, deps)
                return Dict(:i => 1, :n => rand(rng, g.num))
            end

            MockTableGenerators.table_key(g::StatefulGenerator) = :stateful
            MockTableGenerators.num_rows(rng, g::StatefulGenerator, state) = state[:n]

            function MockTableGenerators.emit!(rng, g::StatefulGenerator, deps, state)
                row = (; i=state[:i])
                state[:i] += 1
                return row
            end

            dag = StatefulGenerator(1:5)
            rows = last.(MockTableGenerators.generate(StableRNG(1), dag))
            @test rows == last.(MockTableGenerators.generate(StableRNG(1), dag))

            @test 1 <= length(rows) <= 5
            @test [row.i for row in rows] == 1:length(rows)
        end

        @testset "conditional dependency" begin
            Base.@kwdef struct LetterGenerator <: TableGenerator
                num_alpha::Int
                num_omega::Int
            end

            function MockTableGenerators.visit!(rng, g::LetterGenerator, deps)
                return Dict(:num_alpha => g.num_alpha, :num_omega => g.num_omega)
            end

            MockTableGenerators.table_key(g::LetterGenerator) = :letter

            function MockTableGenerators.num_rows(rng, g::LetterGenerator, state)
                return state[:num_alpha] + state[:num_omega]
            end

            function MockTableGenerators.emit!(rng, g::LetterGenerator, deps, state)
                if state[:num_alpha] > 0
                    state[:num_alpha] -= 1
                    letter = 'α'
                else
                    state[:num_omega] -= 1
                    letter = 'ω'
                end

                return (; letter)
            end

            struct AlphaGenerator <: TableGenerator
                num::Int
            end

            function MockTableGenerators.visit!(rng, g::AlphaGenerator, deps)
                return (; n=(deps[:letter].letter == 'α' ? g.num : 0))
            end

            MockTableGenerators.table_key(g::AlphaGenerator) = :alpha
            MockTableGenerators.num_rows(rng, g::AlphaGenerator, state) = state.n
            MockTableGenerators.emit!(rng, g::AlphaGenerator, deps, state) = (; desc="alpha")

            dag = LetterGenerator(num_alpha=2, num_omega=3) => [AlphaGenerator(1)]
            table_names = first.(MockTableGenerators.generate(StableRNG(1), dag))
            @test table_names == first.(MockTableGenerators.generate(StableRNG(1), dag))

            # An `:alpha` row is created for each `:letter` row using the letter 'α' only
            @test count(==(:letter), table_names) > 2
            @test count(==(:alpha), table_names) == 2

            table_row_pairs = MockTableGenerators.generate(StableRNG(1), dag)
            tables = collect_tables(table_row_pairs)
            @test collect(keys(tables)) == unique(table_names)
            for (name, table) in pairs(tables)
                @test Tables.isrowtable(table)
                @test length(table) == count(==(name), table_names)
            end
            @test tables == generate_tables(StableRNG(1), dag)
        end
    end

    @testset "range" begin
        @test range(2) == 2:2
        @test range(Hour(2)) == Hour(2):Hour(1):Hour(2)
        @test range(1:3) === 1:3
        @test range(1:2:5) === 1:2:5
    end
end
