#!/usr/bin/env ruby

require File.dirname(__FILE__) + '/../spec_helper'

describe Puppet::Status do
  it "should implement find" do
    Puppet::Status.find( :default ).should be_is_a(Puppet::Status)
    Puppet::Status.find( :default ).status["is_alive"].should == true
  end

  it "should default to is_alive is true" do
    Puppet::Status.new.status["is_alive"].should == true
  end

  it "should return a pson hash" do
    Puppet::Status.new.status.to_pson.should == '{"is_alive":true}'
  end

  it "should accept a hash from pson" do
    status = Puppet::Status.new( { "is_alive" => false } )
    status.status.should == { "is_alive" => false }
  end

  it "should have a name" do
    Puppet::Status.new.name
  end

  it "should allow a name to be set" do
    Puppet::Status.new.name = "status"
  end

  it "can do a round-trip serialization via YAML" do
    status = Puppet::Status.new
    new_status = Puppet::Status.convert_from('yaml', status.render('yaml'))
    new_status.instance_variables.each do |attr|
      new_status.instance_variable_get(attr).should == status.instance_variable_get(attr)
    end
  end
end
