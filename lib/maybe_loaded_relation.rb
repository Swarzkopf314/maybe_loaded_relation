require "maybe_loaded_relation/version"

class MaybeLoadedRelation < SimpleDelegator
  # Sometimes the association can be preloaded or not
  # This allows you to avoid hitting the database when it's already preloaded
  # while keeping the usual query syntax, example:

  # pw = MaybeLoadedRelation.abstract_database!(self.product_warehouses) do |pw|
  #   pw.where(warehouse_id: warehouse.id).where("price_net > 0").pluck(:stock_level, :price).first
  # end

  # to avoid using self.class
  KLASS = self
  LOADED_QUERY_METHODS = [:where, :pluck, :find_by, :exists?, :take, :find]

  def self.abstract_database!(relation)
    ret = (yield new(relation))

    if ret.is_a?(KLASS)
      ret.__getobj__
    else
      ret
    end
  end

  # can be any object, but usually it's a relation
  def initialize(obj)
    super
    @search_in_database = obj.is_a?(ActiveRecord::Relation) && !obj.loaded?
  end

  # functor
  def method_missing(method, *args, &block)
    KLASS.new super
  end

  LOADED_QUERY_METHODS.each do |name|

    define_method(name) do |*args|
      if @search_in_database
        ret = __getobj__.send(name, *args)
      else
        ret = KLASS.send("loaded_#{name}", __getobj__, *args)
      end

      KLASS.new ret
    end

  end # each

  def self.parse_string_query(query)
    ary = query.split
    raise "Unsupported query: #{query} - query.split.size != 3" if ary.size != 3
    raise "Unsupported query: #{query} - operation must be one of '>', ''>=', '<', '<='" if !ary.second.in? [">", ">=", "<", "<="]
    ary
  end

  # should return boolean
  def self.realizes_all_opts?(obj, opts)
    case opts
      when Hash
        opts.all? do |atr, query| 
          considered_equal?(query, obj.send(atr))
        end
      when String
        ary = parse_string_query(opts)
        !!obj.send(ary.first).try(ary.second, ary.third.to_f) # "price_net > 0" => obj.price_net.try(">", 0)
      else
        raise "unknown opts!"
    end
  end

  def self.considered_equal?(query, val)
    if query.is_a? Enumerable
      query.include? val
    else
      query == val
    end 
  end

  ### loaded class methods

  def self.loaded_where(relation, opts)
    relation.select do |obj|
      realizes_all_opts?(obj, opts)
    end
  end

  def self.loaded_pluck(relation, *cols)
    relation.map do |obj|
      cols.map {|col| obj.send(col)}
    end
  end

  def self.loaded_find_by(relation, opts)
    relation.find do |obj|
      realizes_all_opts?(obj, opts)
    end
  end

  def self.loaded_exists?(relation)
    relation.any?
  end

  def self.loaded_take(relation)
    relation[0]
  end

  def self.loaded_find(relation, id)
    relation.select do |obj|
      obj.id == id
    end.first.tap{|ret| raise ActiveRecord::RecordNotFound.new("MaybeLoadedRelation: Couldn't find record with given id=#{id}") if ret.nil?}
  end

  raise "You need to define all LOADED_QUERY_METHODS!" if LOADED_QUERY_METHODS.any? {|method| !self.respond_to? "loaded_#{method}"}

end
