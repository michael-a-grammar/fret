defmodule Fret.Note do
  @type note_name :: :c | :d | :e | :f | :g | :a | :b

  @type sharp_note_name :: :f | :c | :g | :d | :a

  @type flat_note_name :: :b | :e | :a | :d | :g

  @type accidental :: :natural | :sharp | :flat

  @type octave :: 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8

  @type frequency :: float()

  @type t :: %__MODULE__{
          name: note_name(),
          accidental: accidental(),
          octave: octave(),
          frequency: frequency()
        }

  @type natural_note :: %__MODULE__{
          name: note_name(),
          accidental: :natural,
          octave: octave(),
          frequency: frequency()
        }

  @type sharp_note :: %__MODULE__{
          name: sharp_note_name(),
          accidental: :sharp,
          octave: octave(),
          frequency: frequency()
        }

  @type flat_note :: %__MODULE__{
          name: flat_note_name(),
          accidental: :flat,
          octave: octave(),
          frequency: frequency()
        }

  @type enharmonic_notes :: {sharp_note(), flat_note()}

  @type note :: natural_note() | enharmonic_notes()

  @type notes :: nonempty_list(note())

  @type query :: %{}

  @note_names [:c, :d, :e, :f, :g, :a, :b]

  @natural_note_names @note_names

  @sharp_note_names [:f, :c, :g, :d, :a]

  @flat_note_names [:b, :e, :a, :d, :g]

  @octaves 0..8

  # The frequency of A4 in hertz
  @reference_note_frequency 440

  @enforce_keys [:name, :accidental, :octave]

  defstruct [:name, :accidental, :octave, :frequency]

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
      %{
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

  @spec get() :: notes()
  def get do
    @octaves
    |> Enum.flat_map(fn octave ->
      @note_names
      |> Enum.map(&{&1, octave})
      |> Enum.chunk_every(2, 1)
      |> Enum.flat_map(fn
        [{:e, _} = e, {:f, _}] ->
          [e]

        [{name, octave}, {next_name, _}] ->
          [{name, octave}, {name, next_name, octave}]

        b ->
          b
      end)
      |> Enum.filter(fn
        {name, 0} when name not in [:a, :b] ->
          false

        {name, _, 0} when name not in [:a, :b] ->
          false

        {name, 8} when name != :c ->
          false

        {_, _, 8} ->
          false

        _ ->
          true
      end)
    end)
    |> then(fn notes ->
      reference_note_index = Enum.find_index(notes, &match?({:a, 4}, &1)) + 1

      notes
      |> Enum.with_index(1)
      |> Enum.map(fn
        {note, index} ->
          semitones_away_from_reference_note = index - reference_note_index

          frequency =
            Float.round(
              2 ** (semitones_away_from_reference_note / 12) * @reference_note_frequency,
              2
            )

          case note do
            {name, octave} ->
              {name, octave, frequency}

            {name, other_name, octave} ->
              {name, other_name, octave, frequency}
          end
      end)
    end)
    |> Enum.map(&new/1)
  end

  @spec find(query()) :: note()
  def find(%{
        name: name,
        accidental: accidental,
        octave: octave
      }) do
    Enum.find(get(), fn
      %__MODULE__{
        name: ^name,
        accidental: ^accidental,
        octave: ^octave
      } ->
        true

      {%__MODULE__{
         name: ^name,
         accidental: ^accidental,
         octave: ^octave
       }, _} ->
        true

      {_,
       %__MODULE__{
         name: ^name,
         accidental: ^accidental,
         octave: ^octave
       }} ->
        true

      _ ->
        false
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

  @spec compare(query(), query()) :: :lt | :eq | :gt
  def compare(query1, query2) do
    [frequency1, frequency2] =
      [query1, query2]
      |> Enum.map(&find/1)
      |> Enum.map(fn
        %__MODULE__{
          frequency: frequency
        } ->
          frequency

        {%__MODULE__{
           frequency: frequency
         }, _} ->
          frequency
      end)

    cond do
      frequency1 < frequency2 ->
        :lt

      frequency1 == frequency2 ->
        :eq

      frequency1 > frequency2 ->
        :gt
    end
  end

  defp new({name, other_name, octave, frequency}) do
    {
      new(name, :sharp, octave, frequency),
      new(other_name, :flat, octave, frequency)
    }
  end

  defp new({name, octave, frequency}) do
    new(name, :natural, octave, frequency)
  end

  defp new(name, accidental, octave, frequency) do
    %__MODULE__{
      name: name,
      accidental: accidental,
      octave: octave,
      frequency: frequency
    }
  end
end
