class Gui::View::MixSettings < Gui::View::Base
  DEFAULT_PARTICIPANTS = 5
  DEFAULT_AMOUNT = 1.0
  MAX_PARTICIPANTS = 100

  import 'java.awt.Component'
  import 'java.awt.Dimension'
  import 'java.awt.Insets'
  import 'javax.swing.JButton'
  import 'javax.swing.JLabel'
  import 'javax.swing.JPanel'
  import 'javax.swing.JPasswordField'
  import 'javax.swing.JSpinner'
  import 'javax.swing.SpinnerModel'
  import 'javax.swing.SpinnerNumberModel'
  import 'javax.swing.JTextField'

  def add
    add_header("Mix Settings")

    add_form_row("Bitcoin Amount (BTC)", amount, 0, width: 100, tool_tip: "Bitcoin amount mixed with other participants and sent to the output address")

    add_form_row("Number of Participants", participants, 1, width: 100, tool_tip: "More participants adds security, but will take more time to complete")

    add_form_row("Input Private Key", input_private_key, 2, tool_tip: "See your wallet software's documentation for exporting private keys")

    add_form_row("Output Address", output_address, 3, tool_tip: "Mixed bitcoin amount will be sent to this address")

    add_form_row("Change Address", change_address, 4, tool_tip: "Un-mixed funds in your wallet sent to this address", last: true)

    add_button_row(start_button, cancel_button)
  end

  def show
    amount.setText((application.amount || DEFAULT_AMOUNT).to_s)
    amount.setEnabled(application.amount.nil?)
    participants.setValue(application.participants || DEFAULT_PARTICIPANTS)
    participants.setEnabled(application.participants.nil?)
    input_private_key.setText("")
  end

  private

  def add_form_row(label_text, component, index, options = {})
    add_row do |parent|
        # parent.add(panel, build_grid_bag_constraints(gridy: 1, fill: :both, anchor: :center, weighty: 1000000))
      container = JPanel.new
      container.setLayout(BoxLayout.new(container, BoxLayout::LINE_AXIS))
      parent.add(container, build_grid_bag_constraints(
        fill: options[:last] ? :horizontal : :horizontal,
        weighty: options[:last] ? 1000000 : 0,
        anchor: :north,
        insets: Insets.new(0, 0, 10, 0),
        gridy: index))

      label = JLabel.new(label_text, JLabel::RIGHT)
      label.setBorder(BorderFactory.createEmptyBorder(0, 0, 0, 20))
      label.setToolTipText(options[:tool_tip]) if options[:tool_tip]
      label.setPreferredSize(Dimension.new(200, 0))
      container.add(label)

      if options[:width]
        component_container = JPanel.new(GridBagLayout.new)
        component_container.add(component, build_grid_bag_constraints(fill: :vertical, anchor: :west))
        component.setPreferredSize(Dimension.new(options[:width], component.getPreferredSize().height))
        container.add(component_container)
      else
        container.add(component)
      end
    end
  end

  def change_address
    @change_address ||= JTextField.new
  end

  def output_address
    @output_address ||= JTextField.new
  end

  def input_private_key
    @input_private_key ||= JPasswordField.new
  end

  def start_button
    @start_button ||= JButton.new("Start Mixing").tap do |start_button|
      start_button.add_action_listener do |e|
        application.show_view(:mixing)
      end
    end
  end

  def cancel_button
    @cancel_button ||= JButton.new("Back").tap do |cancel_button|
      cancel_button.add_action_listener do |e|
        application.show_view(:available_mixes)
      end
    end
  end

  def amount
    @amount ||= JTextField.new
  end

  def participants
    @participants ||= JSpinner.new(build_spinner_model).tap do |participants|
      if participants.getEditor().respond_to?(:getTextField)
        participants.getEditor().getTextField().setHorizontalAlignment(JTextField::LEFT)
      end
      participants.setValue(DEFAULT_PARTICIPANTS)
    end
  end

  def build_spinner_model
    spinner_model_constructor = SpinnerNumberModel.java_class.constructor(Java::int, Java::int, Java::int, Java::int)
    spinner_model_constructor.new_instance(DEFAULT_PARTICIPANTS, 2, MAX_PARTICIPANTS, 1)
  end
end

