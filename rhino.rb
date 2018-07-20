require "securerandom"
require "json"
require "date"
require "fileutils"

require "docopt"

$doc = <<DOCOPT
Rhino.

Usage:
  #{__FILE__} [options] new <text>...
  #{__FILE__} [options] list
  #{__FILE__} new [--tags=<tags>] <text>...
  #{__FILE__} list [--tags=<tags>] <text>...
  #{__FILE__} -h | --help
  #{__FILE__} --version

Options:
  -h --help                              Show this screen.
  --version                              Show version.
  -d --database=<database>               Database file [default: ~/.rhino.json].
  -s --status                            Set the status.
  -t=<tags> --tag=<tags> --tags=<tags>   Set the tags.
DOCOPT

def run
    opts = rhino_opts
    exit if opts.nil?

    db = Database.new opts['--database']
    task = Task.from_hash({
        'text' => opts['<text>'].join(" "),
        'tags' => opts['<tags>'],
    })

    db.upsert task if opts['new']
    db.upsert task if opts['modify']

    if opts['list']
        state = db.get_state
        tasks = state.tasks
            .map { |t| t.to_h(with_priority=true) }
            .sort_by { |t| t['id'] }
            .map.with_index { |t,k| t.update "mask_id" => k }
            .sort_by { |t| t['priority'] }

        puts tasks
        # masked_tasks = state.tasks.

        # puts 'mask_id | priority |                                                            '

        # aliased_tasks = sorted_tasks.map.with_index |t| 
        # sorted_tasks.each { |t| puts t.to_h }
    end
end

def rhino_opts(argv=ARGV)
    begin
        return Docopt::docopt($doc, {:argv => argv})
    rescue Docopt::Exit => e
        puts e.message
    end
    nil
end

class Database
    attr_reader(:db_file, :db_history_file, :lock_file)

    def initialize(db_file)
        raise "invalid db_file" if not db_file.match?(/\.json$/)

        @db_file = File.expand_path(db_file)
        @db_history_file = @db_file.sub(/\.json$/, ".history.json")
        @lock_file = @db_file + '.lock'
    end

    def upsert(new_task)
        self.transaction do |state|
            new_task.touch
            if not (existing_task = state.tasks.find { |v| v.id == new_task.id }).nil?
                state.history << existing_task
                state.tasks.map! { |v| v.id == new_task.id ? new_task : v }
            else
                state.tasks << new_task
            end

            state
        end
    end

    def delete(id)
        self.transaction do |state|
            task = state.tasks.find { |v| v.id == id }
            state.history << task
            state.tasks.delete task
            state
        end
    end

    def transaction
        raise "existing lockfile" if File.exist?(@lock_file)
        FileUtils.touch(@lock_file)

        new_state = yield self.get_state
        self.save_state new_state

        FileUtils.rm(@lock_file)
    end

    def get_state
        state = State.new
        state.tasks = self.load(@db_file)
        state.history = self.load(@db_history_file)
        state
    end

    def save_state(state)
        File.write(@db_file, state.tasks.map(&:to_h).to_json)
        File.write(@db_history_file, state.history.map(&:to_h).to_json)
    end

    def load(json_file)
        data = File.exist?(json_file) ? File.read(json_file) : ""
        return [] if data.length == 0

        JSON.parse(data).map { |v| Task.from_hash v }
    end
end

class State
    @tasks = []
    @history = []
    attr_accessor :tasks, :history;
end

class Task
    attr_reader(
        :id,
        :text,
        :status,
        :urgent,
        :important,
        :tags,
        :created_at,
        :modified_at
    )

    def initialize()
        @id = SecureRandom.uuid
        @text = ''
        @status = :inactive
        @urgent = 1
        @important = 1
        @tags = []

        @created_at = DateTime.now
        @modified_at = DateTime.now
    end

    def priority
        @urgent + @important
    end

    def self.from_hash(hash)
        Task.new.update hash
    end

    def update(hash)
        available_attrs = (Task.instance_methods - Object.methods)
        hash.each_pair do |k, v|
            next if not available_attrs.include? k.to_sym
            self.instance_variable_set('@' + k, v)
        end
        self
    end

    def touch
        @modified_at = DateTime.now
    end

    def to_h(with_priority=false)
        res = self.instance_variables.map do |k|
            [k.to_s.sub(/^@/, ''), self.instance_variable_get(k).to_s]
        end.to_h
        res.update("priority" => self.priority) if with_priority
        res
    end

    def ==(other_task)
        self.instance_variables.all? do |k|
            self.instance_variable_get(k) == other_task.instance_variable_get(k)
        end
    end
end

run if __FILE__ == $0
