defmodule LadybugEx.ListParamsTest do
  @moduledoc """
  Tests for list/array prepared-statement parameters (see
  `~/projects/beep-boop/docs/PRD-ladybug-ex-list-params.md`).

  T1/T2/T3/T5 exercise `term_to_value_named`'s element-type inference; T4
  exercises the G3 error-reporting refactor (unsupported parameters of any
  type return `{:error, message}` naming the parameter instead of raising at
  the NIF boundary).
  """

  use ExUnit.Case
  alias LadybugEx.{Database, Connection}

  setup do
    {:ok, db} = Database.in_memory()
    {:ok, conn} = Connection.new(db)
    {:ok, conn: conn}
  end

  describe "T1 — LIST columns round-trip list params" do
    setup %{conn: conn} do
      {:ok, _} =
        Connection.query(conn, """
          CREATE NODE TABLE ListT(
            id INT64,
            xs INT64[], ys DOUBLE[], bs BOOL[], ss STRING[],
            PRIMARY KEY(id)
          )
        """)

      {:ok, stmt} =
        Connection.prepare(
          conn,
          "CREATE (:ListT {id: $id, xs: $xs, ys: $ys, bs: $bs, ss: $ss})"
        )

      {:ok, stmt: stmt}
    end

    test "Int64/Double/Bool/String list params insert and round-trip", %{conn: conn, stmt: stmt} do
      assert {:ok, _} =
               Connection.execute(conn, stmt,
                 id: 1,
                 xs: [1, 2, 3],
                 ys: [1.5, 2.5, 3.5],
                 bs: [true, false, true],
                 ss: ["alice", "bob"]
               )

      assert {:ok, [row]} =
               Connection.query(conn, "MATCH (t:ListT) RETURN t.xs, t.ys, t.bs, t.ss")

      assert row["t.xs"] == [1, 2, 3]
      assert row["t.ys"] == [1.5, 2.5, 3.5]
      assert row["t.bs"] == [true, false, true]
      assert row["t.ss"] == ["alice", "bob"]
    end
  end

  describe "T2 — FLOAT[N] ARRAY columns accept list params (the motivating case)" do
    test "384-element float list round-trips at float32 tolerance", %{conn: conn} do
      {:ok, _} =
        Connection.query(
          conn,
          "CREATE NODE TABLE Emb384(id INT64, e FLOAT[384], PRIMARY KEY(id))"
        )

      {:ok, stmt} = Connection.prepare(conn, "CREATE (:Emb384 {id: $id, e: $e})")

      vec = for i <- 1..384, do: i / 1000.0

      assert {:ok, _} = Connection.execute(conn, stmt, id: 1, e: vec)

      assert {:ok, [%{"e" => back}]} = Connection.query(conn, "MATCH (n:Emb384) RETURN n.e AS e")

      assert length(back) == 384

      Enum.zip(vec, back)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta expected, actual, 1.0e-6
      end)
    end

    test "8-element float list round-trips at float32 tolerance (cheap fast test)", %{conn: conn} do
      {:ok, _} =
        Connection.query(conn, "CREATE NODE TABLE Emb8(id INT64, e FLOAT[8], PRIMARY KEY(id))")

      {:ok, stmt} = Connection.prepare(conn, "CREATE (:Emb8 {id: $id, e: $e})")

      vec = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8]

      assert {:ok, _} = Connection.execute(conn, stmt, id: 1, e: vec)

      assert {:ok, [%{"e" => back}]} = Connection.query(conn, "MATCH (n:Emb8) RETURN n.e AS e")

      assert length(back) == 8

      Enum.zip(vec, back)
      |> Enum.each(fn {expected, actual} ->
        assert_in_delta expected, actual, 1.0e-6
      end)
    end
  end

  describe "T3 — mixed int+float list promotes to Double" do
    setup %{conn: conn} do
      {:ok, _} =
        Connection.query(conn, "CREATE NODE TABLE MixT(id INT64, ys DOUBLE[], PRIMARY KEY(id))")

      {:ok, stmt} = Connection.prepare(conn, "CREATE (:MixT {id: $id, ys: $ys})")
      {:ok, stmt: stmt}
    end

    test "[1, 2.5] round-trips as [1.0, 2.5], not [1, 2.5]", %{conn: conn, stmt: stmt} do
      assert {:ok, _} = Connection.execute(conn, stmt, id: 1, ys: [1, 2.5])

      assert {:ok, [%{"t.ys" => ys}]} = Connection.query(conn, "MATCH (t:MixT) RETURN t.ys")

      assert ys == [1.0, 2.5]
      assert Enum.all?(ys, &is_float/1)
    end
  end

  describe "T4 — unsupported parameters return {:error, msg} naming the parameter" do
    setup %{conn: conn} do
      {:ok, _} =
        Connection.query(conn, """
          CREATE NODE TABLE ErrT(
            id INT64,
            xs INT64[], ys DOUBLE[], bs BOOL[], ss STRING[],
            PRIMARY KEY(id)
          )
        """)

      {:ok, stmt} =
        Connection.prepare(
          conn,
          "CREATE (:ErrT {id: $id, xs: $xs, ys: $ys, bs: $bs, ss: $ss})"
        )

      {:ok, stmt: stmt}
    end

    defp base_params(overrides) do
      Keyword.merge([id: 1, xs: [1], ys: [1.0], bs: [true], ss: ["x"]], overrides)
    end

    test "heterogeneous list ([1, \"a\"])", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: [1, "a"]))
      assert msg =~ "xs"
      assert msg =~ "heterogeneous"
    end

    test "unsupported non-list value (a map)", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: %{a: 1}))
      assert msg =~ "xs"
    end

    test "unsupported non-list value (a tuple)", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: {1, 2}))
      assert msg =~ "xs"
    end

    test "null-containing list ([1, nil])", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: [1, nil]))
      assert msg =~ "xs"
    end

    test "out-of-range integer in a list", %{conn: conn, stmt: stmt} do
      too_big = 99_999_999_999_999_999_999
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: [too_big]))
      assert msg =~ "xs"
    end

    test "improper list ([1 | 2]) does not panic the NIF boundary", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(xs: [1 | 2]))
      assert msg =~ "xs"
    end

    test "invalid-UTF-8 binary in a string-list position", %{conn: conn, stmt: stmt} do
      bad_binary = <<0xFF, 0xFE>>
      assert {:error, msg} = Connection.execute(conn, stmt, base_params(ss: [bad_binary]))
      assert msg =~ "ss"
    end
  end

  describe "T5 — empty list is rejected" do
    setup %{conn: conn} do
      {:ok, _} =
        Connection.query(conn, "CREATE NODE TABLE EmptyT(id INT64, xs INT64[], PRIMARY KEY(id))")

      {:ok, stmt} = Connection.prepare(conn, "CREATE (:EmptyT {id: $id, xs: $xs})")
      {:ok, stmt: stmt}
    end

    test "empty list parameter is rejected naming the parameter", %{conn: conn, stmt: stmt} do
      assert {:error, msg} = Connection.execute(conn, stmt, id: 1, xs: [])
      assert msg =~ "xs"
    end
  end
end
