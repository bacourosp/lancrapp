module PaypalService
  module PaypalPayment

    PaypalPaymentModel = ::PaypalPayment

    module Entity
      module_function

      PaymentUpdate = EntityUtils.define_builder(
        [:payment_status, :mandatory, :symbol])

      OPT_UPDATE_FIELDS = [
        :order_id,
        :order_date,
        :order_total_cents,
        :authorization_id,
        :authorization_date,
        :authorization_expires_date,
        :authorization_total_cents,
        :payment_id,
        :payment_date,
        :payment_total_cents,
        :fee_total_cents,
        :pending_reason
      ]

      def update(order)
        cent_totals = [:order_total, :authorization_total, :fee_total, :payment_total]
          .reduce({}) do |cent_totals, m_key|
            m = order[m_key]
            cent_totals["#{m_key}_cents".to_sym] = m.cents unless m.nil?
            cent_totals
          end

        payment_update = PaymentUpdate.call(order.merge({payment_status: order[:payment_status].downcase.to_sym}))
        payment_update = payment_update.merge(HashUtils.sub(order, *OPT_UPDATE_FIELDS)).merge(cent_totals)

        return payment_update
      end


      InitialPaymentData = EntityUtils.define_builder(
        [:community_id, :mandatory, :fixnum],
        [:transaction_id, :mandatory, :fixnum],
        [:payer_id, :mandatory, :string],
        [:receiver_id, :mandatory, :string],
        [:payment_status, const_value: :pending],
        [:pending_reason, :string],
        [:order_id, :mandatory, :string],
        [:order_date, :mandatory, :time],
        [:currency, :mandatory, :string],
        [:order_total_cents, :mandatory, :fixnum])

      def initial(order)
        order_total = order[:order_total]
        InitialPaymentData.call(
          order.merge({order_total_cents: order_total.cents, currency: order_total.currency.iso_code}))
      end


      PaypalPayment = EntityUtils.define_builder(
        [:community_id, :mandatory, :fixnum],
        [:transaction_id, :mandatory, :fixnum],
        [:payer_id, :mandatory, :string],
        [:receiver_id, :mandatory, :string],
        [:payment_status, :mandatory, :symbol],
        [:pending_reason, :string],
        [:order_id, :mandatory, :string],
        [:order_date, :mandatory, :time],
        [:order_total, :mandatory, :money],
        [:authorization_id, :string],
        [:authorization_date, :time],
        [:authorization_expires_date, :time],
        [:authorization_total, :money],
        [:payment_id, :string],
        [:payment_date, :time],
        [:payment_total, :money],
        [:fee_total, :money],
        [:commission_status, const_value: :not_charged]) # This is temporarily a fixed const before we have real commission handling

      def from_model(paypal_payment)
        hash = HashUtils.compact(
          EntityUtils.model_to_hash(paypal_payment).merge({
              order_total: MoneyUtil.to_money(paypal_payment[:order_total_cents], paypal_payment[:currency]),
              authorization_total: MoneyUtil.to_money(paypal_payment[:authorization_total_cents], paypal_payment[:currency]),
              fee_total: MoneyUtil.to_money(paypal_payment[:fee_total_cents], paypal_payment[:currency]),
              payment_total: MoneyUtil.to_money(paypal_payment[:payment_total_cents], paypal_payment[:currency]),
              payment_status: paypal_payment[:payment_status].to_sym
            }))

        PaypalPayment.call(hash)
      end

    end

    module Command
      module_function

      def create(community_id, transaction_id, order)
        model = PaypalPaymentModel.create!(
          Entity.initial(
            order
              .merge({community_id: community_id, transaction_id: transaction_id})
        ))
        Entity.from_model(model)
      end

      def update(community_id, transaction_id, order)
        payment_update = Entity.update(order)
        payment = PaypalPaymentModel.where(
            community_id: community_id,
            transaction_id: transaction_id
         ).first

        if payment.nil?
          raise ArgumentError.new("No matching payment to update.")
        end

        payment.update_attributes!(payment_update)

        Entity.from_model(payment.reload)
      end


      ## Privates

      def find_payment(payment_entity)
        payment = if (payment_entity[:order_id])
          PaypalPaymentModel.where(order_id: payment_entity[:order_id]).first
        else
          PaypalPaymentModel.where(authorization_id: payment_entity[:authorization_id]).first
        end

        if (payment && payment_entity[:receiver_id] == payment.receiver_id && payment_entity[:payer_id] == payment.payer_id)
          return payment
        end

        return nil
      end

    end

    module Query
      module_function

      def get(community_id, transaction_id)
        Maybe(PaypalPaymentModel.where(
            community_id: community_id,
            transaction_id: transaction_id
         ).first)
        .map { |model| Entity.from_model(model) }
        .or_else(nil)
      end

      ### DEPRECATED! ###
      def for_transaction(transaction_id)
        Maybe(PaypalPaymentModel.where(transaction_id: transaction_id).first)
        .map { |model| Entity.from_model(model) }
        .or_else(nil)
      end
    end
  end
end
