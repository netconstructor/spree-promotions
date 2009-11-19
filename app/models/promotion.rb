# *Promotion" is a class for managing promotions.
#
# h3. Basic usage
#
# Promotion is automatically applied to order by *PromotionOrderObserver* on each order save.
# and automatically removed if they are no longer applicable to order (checked by #eligible?) or
# amount of promotion credit drops to 0.
# All promotion related calculations should be carried out in special calculator, having different calculators,
# allows for different kinds of promotions.
#
# Calculators for a promotions have promotion_credit passed to it as argument,
# which allow for access to both promotion(as adjustment_source) and order.
#
class Promotion < ActiveRecord::Base
  has_many :credits, :as => :adjustment_source, :dependent => :nullify
  has_calculator
  belongs_to :zone
  belongs_to :promoted, :polymorphic => true

  named_scope :active, {:conditions => [
      "(
         promotions.start_at IS NULL OR promotions.start_at <= ?
       ) AND (
         promotions.end_at IS NULL OR promotions.end_at >= ?
       )",
      Time.now.utc, Time.now.utc
    ]}

  validates_length_of :name, :minimum => 2
  validates_uniqueness_of :name

  # Checks if order is eligible for promotion.
  def eligible?(order)
    eligible = true
    eligible &&= Time.now >= start_at if start_at
    eligible &&= Time.now <= end_at if end_at

    return(eligible)
  end

  # Checks if discount can be combined with other that are already in order.
  # returns true if any of the following is true:
  #  * promotion is combinable,
  #  * there are no other promotions,
  #  * all other promotions are combinable
  def can_combine?(order)
    self.combine && (
      order.credits.empty? ||
      order.credits(:join => :adjustment_source).
      all?{|pc| pc.adjustment_source.combine}
    )
  end

  # Checks if promotion can be added to the order.
  # returns true if
  #  * order is eligible for promotion
  #  * promotion can be combined with other promotions on order
  #  * this promotion is alredy not used
  def can_be_added?(order)
    eligible?(order) &&
      can_combine?(order) &&
      Credit.count(:conditions => {
        :adjustment_source_id => self.id,
        :adjustment_source_type => self.class.name,
        :order_id => order.id
      }) == 0
  end

  # Helper method, crates promotion_credit for order.
  #
  # *WARNING*: this method does not check if credit can be created,
  # use #can_be_added? to check it first
  def create_credit(order)
    credit = order.credits.create({
        :adjustment_source => self,
        :description => I18n.t(name)
      })
    credit
  end
end