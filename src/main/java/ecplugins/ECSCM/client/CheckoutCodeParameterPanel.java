
// CheckoutCodeParameterPanel.java --
//
// CheckoutCodeParameterPanel.java is part of ElectricCommander.
//
// Copyright (c) 2005-2014 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Collection;
import java.util.HashMap;
import java.util.Map;

import com.google.gwt.event.dom.client.ChangeEvent;
import com.google.gwt.event.dom.client.ChangeHandler;
import com.google.gwt.user.client.ui.CheckBox;
import com.google.gwt.user.client.ui.ListBox;
import com.google.gwt.user.client.ui.TextBox;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.domain.ActualParameter;
import com.electriccloud.commander.client.domain.FormalParameter;
import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.ui.ParameterPanel;
import com.electriccloud.commander.gwt.client.ui.ParameterPanelProvider;

public class CheckoutCodeParameterPanel
    extends ComponentBase
    implements ParameterPanel,
        ParameterPanelProvider
{

    //~ Static fields/initializers ---------------------------------------------

    // These are all the formalParameters on the Procedure
    static final String CONFIG          = "config";
    static final String COMMAND         = "command";
    static final String DEST            = "dest";
    static final String REVISION        = "SubversionRevision";
    static final String FILENAME        = "FileName";
    static final String URL             = "SubversionUrl";
    static final String CHECKOUTTYPE    = "CheckoutType";
    static final String IGNOREEXTERNALS = "IgnoreExternals";
    static final String REVISION_OUTPP  = "Revision_outpp";

    //~ Instance fields --------------------------------------------------------

    private FormTable m_formTable;
    private TextBox   config;
    private TextBox   command;
    private TextBox   dest;
    private TextBox   subVersionRevision;
    private TextBox   fileName;
    private TextBox   subVersionUrl;
    private TextBox   revisionOutpp;
    private ListBox   checkoutType;
    private CheckBox  ignoreExternals;

    //~ Methods ----------------------------------------------------------------

    /**
     * This function is called by SDK infrastructure to initialize the UI parts
     * of this component.
     *
     * @return  A widget that the infrastructure should place in the UI; usually
     *          a panel.
     */
    @Override public Widget doInit()
    {

        // FormTable is an SDK specialization of FlexTable that supports moving
        // rows around, setting error messages for individual rows, and various
        // other nifty things.
        //
        // Since it is an EC-provided widget, create one via the ui-factory.
        // The returned object isn't itself a GWT object, but rather a
        // wrapper around a GWT widget class. Use the getWidget() method
        // to retrieve the underlying widget when interacting with other
        // GWT widgets.
        m_formTable        = getUIFactory().createFormTable();
        checkoutType       = new ListBox();
        config             = new TextBox();
        command            = new TextBox();
        dest               = new TextBox();
        subVersionRevision = new TextBox();
        fileName           = new TextBox();
        subVersionUrl      = new TextBox();
        revisionOutpp      = new TextBox();
        ignoreExternals    = new CheckBox();

        // Set svn utility default value
        command.setValue("svn");
        
        // Add items to listbox
        checkoutType.addItem("Directory", "D");
        checkoutType.addItem("File", "F");

        // Mark the checkboxes with default value
        ignoreExternals.setValue(false);

        // The addRow method takes a unique-id for each row being added to the
        // table. This can be used to find the row in the table later, or
        // for moving rows around. See the FormTable class for details.
        m_formTable.addFormRow("1", "Configuration:", config, true,
            "This parameter must have the name of the configuration created in the \"Plugin Configuration Parameters\" section for this plugin.");
        m_formTable.addFormRow("2", "SVN command line utility:", command, false,
            "Absolute path to the svn command line tool.");
        m_formTable.addFormRow("3", "Destination Directory:", dest, false,
            "Indicate the path relative to the job's workspace where the source tree will be created.");
        m_formTable.addFormRow("4", "Revision:", subVersionRevision, false,
            "The revision number to checkout. If multiple repositories are given, revision numbers of each repository can be provided, separated with a \"|\" character");
        m_formTable.addFormRow("5", "Checkout Type:", checkoutType, true,
            "Select the type of checkout you want to perform.");
        m_formTable.addFormRow("6", "File(s) to download:", fileName, true,
            "Name of the file you want to download from the repository (Only used when the Checkout type is marked as \"File\"). you can provide multiple files if you separate them with a \"|\" character.");
        m_formTable.addFormRow("7", "Repository:", subVersionUrl, true,
            "This is the location of the subversion repository directory to use. Note: In case you need to checkout code from several svn repositories separate them with a \"|\" character. Example: svn://svnserver/test/perl files|svn://svnserver/test/ruby files.");
        m_formTable.addFormRow("8", "Revision (output property path):",
            revisionOutpp, false,
            "Property where the last revision number will be stored.");
        m_formTable.addFormRow("9", "Ignore Externals:", ignoreExternals, false,
            "If checked it tells Subversion to ignore externals definitions and the external working copies managed by them.");

        // set row 6 invisible by default
        m_formTable.setRowVisible("6", false);

        // Add click handler to handle when a user clicks the checkbox
        checkoutType.addChangeHandler(new ChangeHandler() {
                @Override public void onChange(ChangeEvent event)
                {
                    int    index   = checkoutType.getSelectedIndex();
                    String current = checkoutType.getValue(index);

                    m_formTable.setRowVisible("6", current.equals("F"));
                }
            });

        return m_formTable.asWidget();
    }

    /**
     * Performs validation of user supplied data before submitting the form.
     *
     * <p>This function is called after the user hits submit.</p>
     *
     * @return  true if checks succeed, false otherwise
     */
    @Override public boolean validate()
    {
        int    index   = checkoutType.getSelectedIndex();
        String current = checkoutType.getValue(index);

        if (config.getValue()
                  .trim()
                  .equals("")) {
            m_formTable.setErrorMessage("1", "This field is required.");

            return false;
        }

        if (subVersionUrl.getValue()
                         .equals("")) {
            m_formTable.setErrorMessage("7", "This field is required.");

            return false;
        }

        // File is only required when the checkout option is File
        if (current.equals("F")) {

            if (fileName.getValue()
                        .trim()
                        .equals("")) {
                m_formTable.setErrorMessage("6", "This field is required.");

                return false;
            }
        }

        return true;
    }

    /**
     * Straight forward function usually just return this;
     *
     * @return  straight forward function usually just return this;
     */
    @Override public ParameterPanel getParameterPanel()
    {
        return this;
    }

    /**
     * Gets the values of the parameters that should map 1-to-1 to the formal
     * parameters on the object being called. Transform user input into a map of
     * parameter names and values.
     *
     * <p>This function is called after the user hits submit and validation has
     * succeeded.</p>
     *
     * @return  The values of the parameters that should map 1-to-1 to the
     *          formal parameters on the object being called.
     */
    @Override public Map<String, String> getValues()
    {
        Map<String, String> values  = new HashMap<String, String>();
        int                 index   = checkoutType.getSelectedIndex();
        boolean             checked = ignoreExternals.getValue();

        values.put(CONFIG, config.getValue());
        values.put(COMMAND, command.getValue());
        values.put(DEST, dest.getValue());
        values.put(REVISION, subVersionRevision.getValue());
        values.put(FILENAME, fileName.getValue());
        values.put(URL, subVersionUrl.getValue());
        values.put(REVISION_OUTPP, revisionOutpp.getValue());
        values.put(CHECKOUTTYPE, checkoutType.getValue(index));

        if (checked) {
            values.put(IGNOREEXTERNALS, "1");
        }
        else {
            values.put(IGNOREEXTERNALS, "0");
        }

        return values;
    }

    /**
     * Push actual parameters into the panel implementation.
     *
     * <p>This is used when editing an existing object to show existing content.
     * </p>
     *
     * @param  actualParameters  Actual parameters assigned to this list of
     *                           parameters.
     */
    @Override public void setActualParameters(
            Collection<ActualParameter> actualParameters)
    {

        // Store actual params into a hash for easy retrieval later
        Map<String, String> actualsMap = new HashMap<String, String>();

        for (ActualParameter actualParameter : actualParameters) {
            actualsMap.put(actualParameter.getName(),
                actualParameter.getValue());
        }

        // Populate the form based on if we are editing an existing object or
        // creating a new object
        if (actualsMap.size() > 0) {

            // Set the project
            int index = 0;

            if (actualsMap.get(CHECKOUTTYPE)
                          .equals("F")) {
                m_formTable.setRowVisible("6", true);
                index = 1;
            }

            config.setValue(actualsMap.get(CONFIG));
            command.setValue(actualsMap.get(COMMAND));
            dest.setValue(actualsMap.get(DEST));
            subVersionRevision.setValue(actualsMap.get(REVISION));
            fileName.setValue(actualsMap.get(FILENAME));
            subVersionUrl.setValue(actualsMap.get(URL));
            revisionOutpp.setValue(actualsMap.get(REVISION_OUTPP));
            checkoutType.setSelectedIndex(index);
            ignoreExternals.setValue(actualsMap.get(IGNOREEXTERNALS)
                                               .equals("1"));
        }
    }

    /**
     * Push form parameters into the panel implementation.
     *
     * <p>This is used when creating a new object and showing default values.
     * </p>
     *
     * @param  formalParameters  Formal parameters on the target object.
     */
    @Override public void setFormalParameters(
            Collection<FormalParameter> formalParameters) { }
}
