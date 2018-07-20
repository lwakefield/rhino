require "pp"
require "tempfile"

require "./rhino"

describe "rhino_opts" do
  it "gets options correctly" do
    expect(rhino_opts("new foo")).to include({
      "new" => true,
      "<text>" => ["foo"]
    })
    [
      "new --tags=bar foo",
      "new --tag=bar foo",
      "new -tbar foo",
      "new -t bar foo",
    ].each do |argv|
      expect(rhino_opts(argv)). to include({
        "new" => true,
        "<text>" => ["foo"],
        "--tags" => "bar"
      })
    end
  end
end

describe "Task" do
  it "intializes correctly" do
    expect(Task.new.id).to be_truthy
    expect(Task.new.id).not_to eql Task.new.id
  end
  it "serializes correctly" do
    expect(Task.new.to_h).to be_a Hash
  end
  it "deserializes correctly" do
    t = Task.from_hash({ "id" => "foo" })
    expect(t.id).to eql "foo"
  end
  it "from_hash ignores some attributes" do
    t = Task.from_hash({ "id" => "foo", "bar" => "baz"})
    expect(t.id).to eql "foo"
    expect(t.instance_variable_defined? '@bar').to be_falsey
  end
end

describe "Rhino" do
  it "initializes correctly" do
    db_file = Tempfile.new(["rhino", ".json"]).path
    db = Database.new db_file
    expect(db.instance_variable_get("@db_file")).to eql db_file
    expect(db.instance_variable_get("@db_history_file")).to include "history"
    expect(db.instance_variable_get("@lock_file")).to include "lock"
  end

  it "loads empty db correctly" do
    db_file = Tempfile.new(["rhino", ".json"]).path
    db = Database.new db_file
    expect(db.load db_file).to eql []
  end

  it "loads db correctly" do
    db_file = Tempfile.new(["rhino", ".json"])
    File.write(db_file.path, '[{"id": "foo"}]')

    db = Database.new db_file.path
    tasks = db.load db_file.path
    expect(tasks).to be_an Array
    expect(tasks[0]).to be_a Task
    expect(tasks[0].id).to eql "foo"
  end

  it "upserts correctly" do
    db = Database.new Tempfile.new(["rhino", ".json"]).path
    original_task = Task.from_hash({"id" => "foo", "created_at" => DateTime.new(2004)})
    updated_task = original_task.clone.update({"text" => "hello world"})
    File.write(db.db_file, "[#{original_task.to_h.to_json}]")

    allow(DateTime).to receive(:now).and_return(DateTime.new 2005)
    # # TODO: work out hwo to spy/monkeypatch...
    # # spy(FileUtils:touch)
    db.upsert updated_task

    expect(JSON.parse File.read(db.db_file)).to eql(
      [updated_task.clone.update("modified_at" => DateTime.new(2005)).to_h]
    )
    expect(JSON.parse File.read(db.db_history_file)).to eql(
      [original_task.to_h]
    )
  end
end
