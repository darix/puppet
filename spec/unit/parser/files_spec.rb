#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../../spec_helper'

require 'puppet/parser/files'

describe Puppet::Parser::Files do

  before do
    @basepath = Puppet.features.posix? ? "/somepath" : "C:/somepath"
  end

  describe "when searching for templates" do
    it "should return fully-qualified templates directly" do
      Puppet::Parser::Files.expects(:modulepath).never
      Puppet::Parser::Files.find_template(@basepath + "/my/template").should == @basepath + "/my/template"
    end

    it "should return the template from the first found module" do
      mod = mock 'module'
      Puppet::Node::Environment.new.expects(:module).with("mymod").returns mod

      mod.expects(:template).returns("/one/mymod/templates/mytemplate")
      Puppet::Parser::Files.find_template("mymod/mytemplate").should == "/one/mymod/templates/mytemplate"
    end

    it "should return the file in the templatedir if it exists" do
      Puppet.settings.expects(:value).with(:templatedir, nil).returns("/my/templates")
      Puppet[:modulepath] = "/one:/two"
      File.stubs(:directory?).returns(true)
      FileTest.stubs(:exist?).returns(true)
      Puppet::Parser::Files.find_template("mymod/mytemplate").should == "/my/templates/mymod/mytemplate"
    end

    it "should not raise an error if no valid templatedir exists and the template exists in a module" do
      mod = mock 'module'
      Puppet::Node::Environment.new.expects(:module).with("mymod").returns mod

      mod.expects(:template).returns("/one/mymod/templates/mytemplate")
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(nil)

      Puppet::Parser::Files.find_template("mymod/mytemplate").should == "/one/mymod/templates/mytemplate"
    end

    it "should return unqualified templates if they exist in the template dir" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should == "/my/templates/mytemplate"
    end

    it "should only return templates if they actually exist" do
      FileTest.expects(:exist?).with("/my/templates/mytemplate").returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should == "/my/templates/mytemplate"
    end

    it "should return nil when asked for a template that doesn't exist" do
      FileTest.expects(:exist?).with("/my/templates/mytemplate").returns false
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Parser::Files.find_template("mytemplate").should be_nil
    end

    it "should search in the template directories before modules" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with(nil).returns(["/my/templates"])
      Puppet::Module.expects(:find).never
      Puppet::Parser::Files.find_template("mytemplate")
    end

    it "should accept relative templatedirs" do
      FileTest.stubs(:exist?).returns true
      Puppet[:templatedir] = "my/templates"
      File.expects(:directory?).with(File.join(Dir.getwd,"my/templates")).returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == File.join(Dir.getwd,"my/templates/mytemplate")
    end

    it "should use the environment templatedir if no module is found and an environment is specified" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with("myenv").returns(["/myenv/templates"])
      Puppet::Parser::Files.find_template("mymod/mytemplate", "myenv").should == "/myenv/templates/mymod/mytemplate"
    end

    it "should use first dir from environment templatedir if no module is found and an environment is specified" do
      FileTest.stubs(:exist?).returns true
      Puppet::Parser::Files.stubs(:templatepath).with("myenv").returns(["/myenv/templates", "/two/templates"])
      Puppet::Parser::Files.find_template("mymod/mytemplate", "myenv").should == "/myenv/templates/mymod/mytemplate"
    end

    it "should use a valid dir when templatedir is a path for unqualified templates and the first dir contains template" do
      Puppet::Parser::Files.stubs(:templatepath).returns(["/one/templates", "/two/templates"])
      FileTest.expects(:exist?).with("/one/templates/mytemplate").returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == "/one/templates/mytemplate"
    end

    it "should use a valid dir when templatedir is a path for unqualified templates and only second dir contains template" do
      Puppet::Parser::Files.stubs(:templatepath).returns(["/one/templates", "/two/templates"])
      FileTest.expects(:exist?).with("/one/templates/mytemplate").returns(false)
      FileTest.expects(:exist?).with("/two/templates/mytemplate").returns(true)
      Puppet::Parser::Files.find_template("mytemplate").should == "/two/templates/mytemplate"
    end

    it "should use the node environment if specified" do
      mod = mock 'module'
      Puppet::Node::Environment.new("myenv").expects(:module).with("mymod").returns mod

      mod.expects(:template).returns("/my/modules/mymod/templates/envtemplate")

      Puppet::Parser::Files.find_template("mymod/envtemplate", "myenv").should == "/my/modules/mymod/templates/envtemplate"
    end

    it "should return nil if no template can be found" do
      Puppet::Parser::Files.find_template("foomod/envtemplate", "myenv").should be_nil
    end

    after { Puppet.settings.clear }
  end

  describe "when searching for manifests" do
    it "should ignore invalid modules" do
      mod = mock 'module'
	  env = Puppet::Node::Environment.new
      env.expects(:module).with("mymod").raises(Puppet::Module::InvalidName, "name is invalid")
      Puppet.expects(:value).with(:modulepath).never
      Dir.stubs(:glob).returns %w{foo}
      Puppet::Parser::Files.find_manifests_in_modules("mymod/init.pp", env)
    end
  end

  describe "when searching for manifests in a found module" do
    it "should return the name of the module and the manifests from the first found module" do
      mod = Puppet::Module.new("mymod")
      env = Puppet::Node::Environment.new
      env.expects(:module).with("mymod").returns mod
      mod.expects(:match_manifests).with("init.pp").returns(%w{/one/mymod/manifests/init.pp})
      Puppet::Parser::Files.find_manifests_in_modules("mymod/init.pp", env).should == ["mymod", ["/one/mymod/manifests/init.pp"]]
    end

    after { Puppet.settings.clear }
  end
end
