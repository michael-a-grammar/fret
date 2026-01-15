defmodule Fret.Note do
  @type note_name :: :c | :d | :e | :f | :g | :a | :b

  @type sharp_note_name :: :f | :c | :g | :d | :a

  @type flat_note_name :: :b | :e | :a | :d | :g

  @type accidental :: :natural | :sharp | :flat

  @type octave :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8

  @type t :: %__MODULE__{
          name: note_name(),
          accidental: accidental(),
          octave: octave()
        }

  @type natural_note :: %__MODULE__{
          name: note_name(),
          accidental: :natural,
          octave: octave()
        }

  @type sharp_note :: %__MODULE__{
          name: sharp_note_name(),
          accidental: :sharp,
          octave: octave()
        }

  @type flat_note :: %__MODULE__{
          name: flat_note_name(),
          accidental: :flat,
          octave: octave()
        }

  @type enharmonic_note :: {sharp_note(), flat_note()}

  @type note :: natural_note() | enharmonic_note()

  @type notes :: nonempty_list(note())

  @note_names [:c, :d, :e, :f, :g, :a, :b]

  @natural_note_names @note_names

  @sharp_note_names [:f, :c, :g, :d, :a]

  @flat_note_names [:b, :e, :a, :d, :g]

  @octaves 0..8

  # The frequency of A4 in hertz
  @reference_note_frequency 440

  @enforce_keys [:name, :accidental, :octave]

  defstruct [:name, :accidental, :octave]

  defguard is_natural_note(note)
           when is_struct(note, __MODULE__) and
                  note.name in @natural_note_names and
                  note.accidental == :natural and
                  note.octave in @octaves

  defguard is_sharp_note(note)
           when is_struct(note, __MODULE__) and
                  note.name in @sharp_note_names and
                  note.accidental == :sharp and
                  note.octave in @octaves

  defguard is_flat_note(note)
           when is_struct(note, __MODULE__) and
                  note.name in @flat_note_names and
                  note.accidental == :flat and
                  note.octave in @octaves

  defguard is_enharmonic_note(note)
           when is_tuple(note) and
                  note
                  |> elem(0)
                  |> is_sharp_note() and
                  note
                  |> elem(1)
                  |> is_flat_note()

  defguard is_note(note)
           when is_natural_note(note) or
                  is_sharp_note(note) or
                  is_flat_note(note) or
                  is_enharmonic_note(note)

  def sigil_n(string, []), do: sigil_NOTE(string, [])

  def sigil_NOTE(string, []) do
    parse_accidental = fn accidental ->
      accidental
      |> String.downcase()
      |> case do
        "" ->
          :natural

        "#" ->
          :sharp

        "b" ->
          :flat
      end
      |> then(&{:ok, &1})
    end

    parse_name = fn name, accidental ->
      name
      |> String.downcase()
      |> then(fn name ->
        try do
          String.to_existing_atom(name)
        rescue
          _ in ArgumentError ->
            {:error, "can not parse name"}
        end
      end)
      |> then(fn name ->
        cond do
          accidental == :natural and name in @note_names ->
            {:ok, name}

          accidental == :sharp and name in @sharp_note_names ->
            {:ok, name}

          accidental == :flat and name in @flat_note_names ->
            {:ok, name}

          true ->
            {:error, "can not parse name"}
        end
      end)
    end

    parse_octave = fn octave ->
      octave
      |> Integer.parse()
      |> then(&{:ok, elem(&1, 0)})
    end

    with %{"name" => name, "accidental" => accidental, "octave" => octave} <-
           Regex.named_captures(
             ~r/^(?<name>[a-gA-G]{1,1})(?<accidental>#|b|)(?<octave>[0-8]{1,1})$/,
             string
           ),
         {:ok, accidental} <- parse_accidental.(accidental),
         {:ok, name} <- parse_name.(name, accidental),
         {:ok, octave} <- parse_octave.(octave) do
      %__MODULE__{
        name: name,
        accidental: accidental,
        octave: octave
      }
    else
      nil ->
        {:error, "can not parse note"}

      error ->
        error
    end
  end

  @spec notes() :: notes()
  def notes do
    @octaves
    |> Enum.flat_map(fn octave ->
      @note_names
      |> Enum.map(&{&1, octave})
      |> Enum.chunk_every(2, 1)
      |> Enum.flat_map(fn
        [{:e, _} = e, {:f, _}] ->
          [e]

        [note, next_note] ->
          [note, {{note, :sharp}, {next_note, :flat}}]

        b ->
          b
      end)
      |> Enum.filter(fn
        {note_name, 0} when note_name not in [:a, :b] ->
          false

        {{{note_name, 0}, _}, _} when note_name not in [:a, :b] ->
          false

        {note_name, 8} when note_name != :c ->
          false

        {{{_, 8}, _}, _} ->
          false

        _ ->
          true
      end)
    end)
    |> then(fn notes ->
      reference_note_index = Enum.find_index(notes, &match?({:a, 4}, &1)) + 1

      notes
      |> Enum.with_index(1)
      |> Enum.each(fn
        {_, index} = note ->
          semitones_away_from_reference_note = index - reference_note_index

          IO.inspect(
            2 ** (semitones_away_from_reference_note / 12) * @reference_note_frequency,
            label: "#{inspect(note)}"
          )
      end)

      notes
    end)
    |> Enum.map(fn
      {{{_, _} = note, accidental}, {{_, _} = next_note, next_accidental}} ->
        {to_struct(note, accidental), to_struct(next_note, next_accidental)}

      {_, _} = note ->
        to_struct(note)
    end)
  end

  # @spec from(note()) :: notes()
  # def from(note) do
  #   note
  #   |> find_note_index()
  #   |> then(fn
  #     note_index ->
  #       Enum.slide(@notes, note_index..-1//1, 0)
  #   end)
  # end

  @spec compare(notes(), note(), note()) :: :lt | :eq | :gt
  def compare(notes, note1, note2) do
    [note1_index, note2_index] =
      [note1, note2]
      |> Enum.map(&find_note_index(notes, &1))

    cond do
      note1_index < note2_index ->
        :lt

      note1_index == note2_index ->
        :eq

      note1_index > note2_index ->
        :gt
    end
  end

  def find_note_index(notes, note) when is_natural_note(note) or is_enharmonic_note(note) do
    Enum.find_index(notes, &(&1 == note))
  end

  def find_note_index(notes, %__MODULE__{} = note)
      when is_sharp_note(note) or is_flat_note(note) do
    notes
    |> Enum.find(fn
      {^note, _} ->
        true

      {_, ^note} ->
        true

      _ ->
        false
    end)
    |> then(&find_note_index(notes, &1))
  end

  defp to_struct({name, octave}, accidental \\ :natural) do
    %__MODULE__{
      name: name,
      accidental: accidental,
      octave: octave
    }
  end
end
