require "spec_helper"

describe TestBoosters::Rspec::Booster do

  subject(:booster) { TestBoosters::Rspec::Booster.new(0, 3) }

  let(:specs_path) { "/tmp/rspec_tests" }
  let(:split_configuration_path) { "/tmp/split_configuration.json" }

  before do
    FileUtils.rm_f(split_configuration_path)
    FileUtils.rm_rf(specs_path)
    FileUtils.mkdir_p(specs_path)

    ENV["SPEC_PATH"] = specs_path
    ENV["RSPEC_SPLIT_CONFIGURATION_PATH"] = split_configuration_path
  end

  describe "#specs_path" do
    context "when the SPEC_PATH environment variable is set" do
      it "returns its values" do
        expect(booster.specs_path).to eq(specs_path)
      end
    end

    context "when the SPEC_PATH environment variable is not set" do
      before { ENV.delete("SPEC_PATH") }

      it "returns the relative 'spec' folder" do
        expect(booster.specs_path).to eq("spec")
      end
    end
  end

  describe "#split_configuration_path" do

    context "when the RSPEC_SPLIT_CONFIGURATION_PATH environment variable is set" do
      it "returns its values" do
        expect(booster.split_configuration_path).to eq(split_configuration_path)
      end
    end

    context "when the RSPEC_SPLIT_CONFIGURATION_PATH environment variable is not set" do
      before { ENV.delete("RSPEC_SPLIT_CONFIGURATION_PATH") }

      it "returns the path from the home directory" do
        expect(booster.split_configuration_path).to eq("#{ENV["HOME"]}/rspec_split_configuration.json")
      end
    end
  end

  describe "#all_specs" do
    before do
      Support::RspecFilesFactory.create(:path => "#{specs_path}/a_spec.rb")
      Support::RspecFilesFactory.create(:path => "#{specs_path}/lib/darth_vader/c_spec.rb")
      Support::RspecFilesFactory.create(:path => "#{specs_path}/b_spec.rb")
    end

    it "returns all the files" do
      expect(booster.all_specs).to eq [
        "#{specs_path}/a_spec.rb",
        "#{specs_path}/b_spec.rb",
        "#{specs_path}/lib/darth_vader/c_spec.rb"
      ]
    end
  end

  describe "#split_configuration" do
    before do
      Support::SplitConfigurationFactory.create(
        :path => split_configuration_path,
        :content => [
          { :files => ["#{specs_path}/a_spec.rb"] },
          { :files => ["#{specs_path}/b_spec"] },
          { :files => [] }
        ])
    end

    it "returns an instance of the split configuration" do
      expect(booster.split_configuration).to be_instance_of(TestBoosters::SplitConfiguration)
    end
  end

  describe "#all_leftover_specs" do
    context "when the split configuration has the same files as the spec directory" do
      before do
        Support::RspecFilesFactory.create(:path => "#{specs_path}/a_spec.rb")
        Support::RspecFilesFactory.create(:path => "#{specs_path}/b_spec.rb")
        Support::RspecFilesFactory.create(:path => "#{specs_path}/lib/darth_vader/c_spec.rb")

        Support::SplitConfigurationFactory.create(
          :path => split_configuration_path,
          :content => [
            { :files => ["#{specs_path}/a_spec.rb"] },
            { :files => ["#{specs_path}/b_spec.rb"] },
            { :files => ["#{specs_path}/lib/darth_vader/c_spec.rb"] }
          ])
      end

      it "returns empty array" do
        expect(booster.all_leftover_specs).to eq([])
      end
    end

    context "when there are more files in the directory then in the split configuration" do
      before do
        Support::RspecFilesFactory.create(:path => "#{specs_path}/a_spec.rb")
        Support::RspecFilesFactory.create(:path => "#{specs_path}/b_spec.rb")
        Support::RspecFilesFactory.create(:path => "#{specs_path}/lib/darth_vader/c_spec.rb")

        Support::SplitConfigurationFactory.create(
          :path => split_configuration_path,
          :content => [])
      end

      it "return the missing files" do
        expect(booster.all_leftover_specs).to eq([
          "#{specs_path}/a_spec.rb",
          "#{specs_path}/b_spec.rb",
          "#{specs_path}/lib/darth_vader/c_spec.rb"
        ])
      end
    end

    context "when there are more files in the split configuration then in the specs dir" do
      before do
        Support::RspecFilesFactory.create(:path => "#{specs_path}/a_spec.rb")

        Support::SplitConfigurationFactory.create(
          :path => split_configuration_path,
          :content => [
            { :files => ["#{specs_path}/a_spec.rb"] },
            { :files => ["#{specs_path}/b_spec.rb"] },
            { :files => ["#{specs_path}/lib/darth_vader/c_spec.rb"] }
          ])
      end

      it "returns empty array" do
        expect(booster.all_leftover_specs).to eq([])
      end
    end
  end

  describe "#threads" do
    before do
      # known files
      Support::RspecFilesFactory.create(:path => "#{specs_path}/a_spec.rb")
      Support::RspecFilesFactory.create(:path => "#{specs_path}/lib/darth_vader/c_spec.rb")

      # unknown files
      Support::RspecFilesFactory.create(:path => "#{specs_path}/x_spec.rb")
      Support::RspecFilesFactory.create(:path => "#{specs_path}/y_spec.rb")
      Support::RspecFilesFactory.create(:path => "#{specs_path}/lib/palpatine/y_spec.rb")

      Support::SplitConfigurationFactory.create(
        :path => split_configuration_path,
        :content => [
          { :files => ["#{specs_path}/a_spec.rb"] },
          { :files => ["#{specs_path}/lib/darth_vader/c_spec.rb"] },
          { :files => ["#{specs_path}/b_spec.rb"] }
        ])
    end

    it "returns 3 threads" do
      expect(booster.threads.count).to eq(3)
    end

    it "returns instances of booster threads" do
      booster.threads.each do |thread|
        expect(thread).to be_instance_of(TestBoosters::Rspec::Thread)
      end
    end

    it "passes existing files from split configuration to threads" do
      threads = booster.threads

      expect(threads[0].files_from_split_configuration).to eq(["#{specs_path}/a_spec.rb"])
      expect(threads[1].files_from_split_configuration).to eq(["#{specs_path}/lib/darth_vader/c_spec.rb"])
      expect(threads[2].files_from_split_configuration).to eq([])
    end

    it "passes leftover files to specs" do
      threads = booster.threads

      expect(threads[0].leftover_files).to eq(["#{specs_path}/y_spec.rb"])
      expect(threads[1].leftover_files).to eq(["#{specs_path}/x_spec.rb"])
      expect(threads[2].leftover_files).to eq(["#{specs_path}/lib/palpatine/y_spec.rb"])
    end
  end

  describe "#run" do
    before do
      @threads = [double, double, double]
      @booster = TestBoosters::Rspec::Booster.new(1, 3)

      allow(@booster).to receive(:threads).and_return(@threads)
      allow(@threads[1]).to receive(:run)
    end

    it "displays title" do
      expect { @booster.run }.to output(/RSpec Booster v#{TestBoosters::VERSION}/).to_stdout
    end

    it "invokes run on the current thread" do
      expect(@threads[1]).to receive(:run)

      @booster.run
    end
  end
end