
// Reports.java --
//
// Reports.java is part of ElectricCommander.
//
// Copyright (c) 2005-2014 Electric Cloud, Inc.
// All rights reserved.
//

package ecplugins.ECSCM.client;

import java.util.Map;

import com.google.gwt.user.client.ui.Anchor;
import com.google.gwt.user.client.ui.DecoratorPanel;
import com.google.gwt.user.client.ui.HTML;
import com.google.gwt.user.client.ui.Label;
import com.google.gwt.user.client.ui.VerticalPanel;
import com.google.gwt.user.client.ui.Widget;

import com.electriccloud.commander.client.ChainedCallback;
import com.electriccloud.commander.client.domain.Property;
import com.electriccloud.commander.client.domain.PropertySheet;
import com.electriccloud.commander.client.requests.GetPropertiesRequest;
import com.electriccloud.commander.client.responses.CommanderError;
import com.electriccloud.commander.client.responses.PropertySheetCallback;
import com.electriccloud.commander.gwt.client.ComponentBase;
import com.electriccloud.commander.gwt.client.protocol.xml.RequestSerializerImpl;
import com.electriccloud.commander.gwt.client.ui.FormTable;
import com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder;

import static com.electriccloud.commander.gwt.client.util.CommanderUrlBuilder.createUrl;

/**
 */
public class Reports
    extends ComponentBase
{

    //~ Instance fields --------------------------------------------------------

    private PropertySheet m_responseForChangelog;
    private PropertySheet m_responseForRepoUrls;

    //~ Methods ----------------------------------------------------------------

    @Override public Widget doInit()
    {

        /* Renders the component. */
        DecoratorPanel rootPanel = new DecoratorPanel();
        VerticalPanel  vPanel    = new VerticalPanel();

        vPanel.setBorderWidth(0);

        String              jobId      = getGetParameter("jobId");
        CommanderUrlBuilder urlBuilder = createUrl("jobDetails.php")
                .setParameter("jobId", jobId);

        vPanel.add(new Anchor("Job: " + jobId, urlBuilder.buildString()));

        Widget htmlH1 = new HTML("<h1>Subversion Changelog</h1>");

        vPanel.add(htmlH1);

        Widget htmlLabel = new HTML(
                "<p><b>SVN changelogs associated with the ElectricCommander job:</b></p>");

        vPanel.add(htmlLabel);

        FormTable formTable = getUIFactory().createFormTable();

        vPanel.add(formTable.getWidget());
        rootPanel.add(vPanel);
        callback(formTable);

        return rootPanel;
    }

    private void callback(final FormTable formTable)
    {
        String jobId = getGetParameter("jobId");

        debug("jobId: " + jobId);

        GetPropertiesRequest reqChangelog = getRequestFactory()
                .createGetPropertiesRequest();

        reqChangelog.setPath("/jobs/" + jobId + "/ecscm_changeLogs");
        reqChangelog.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {
                    m_responseForChangelog = response;
                }

                @Override public void handleError(CommanderError error)
                {
                    debug("Error trying to access property");

                    // noinspection HardCodedStringLiteral
                    formTable.addRow("0", new Label("No changelogs Found"));
                }
            });

        // GetProperties request to get /jobs/jobId/ecscm_repositoryUrls
        GetPropertiesRequest reqRepoUrls = getRequestFactory()
                .createGetPropertiesRequest();

        reqRepoUrls.setPath("/jobs/" + jobId + "/ecscm_repositoryUrls");
        reqRepoUrls.setCallback(new PropertySheetCallback() {
                @Override public void handleResponse(PropertySheet response)
                {
                    m_responseForRepoUrls = response;
                }

                @Override public void handleError(CommanderError error) {
                    debug("Error trying to access property");

                    // noinspection HardCodedStringLiteral
                    formTable.addRow("0", new Label("No changelogs Found"));
                }
            });
        debug("SVN Reports doInit: Issuing Commander request: "
                + new RequestSerializerImpl().serialize(reqChangelog));
        debug("SVN Reports doInit: Issuing Commander request: "
                + new RequestSerializerImpl().serialize(reqRepoUrls));

        ChainedCallback chainedCallback = new ChainedCallback() {
            @Override public void onComplete()
            {
                parseResponse(m_responseForChangelog, m_responseForRepoUrls,
                    formTable);
            }
        };
        doRequest(chainedCallback, reqChangelog, reqRepoUrls);
    }

    private void debug(String msg)
    {

        if (getLog().isDebugEnabled()) {
            getLog().debug(msg);
        }
    }

    private void parseResponse(
            PropertySheet responseForChangelog,
            PropertySheet responseForRepoUrls,
            FormTable     form)
    {
        debug("getProperties request returned "
                + responseForChangelog.getProperties()
                                      .size() + " properties");
        debug("getProperties request returned "
                + responseForRepoUrls.getProperties()
                                     .size() + " properties");

        if (responseForChangelog.getProperties().size() == 0) {
            form.addRow("0", new Label("No changelogs Found"));

            return;
        }

        for (Property p : responseForChangelog.getProperties()
                                    .values()) {
            String scmUrl    = p.getName();
            String changeLog = p.getValue();

            Property repositoryName = responseForRepoUrls.getProperties().get(scmUrl);
            if (repositoryName != null) {
                scmUrl = repositoryName.getValue();
            }

            HTML htmlH1 = new HTML("<h3>" + scmUrl + "</h3> <pre>" + changeLog
                        + "</pre>");

            form.addRow("0", htmlH1);
            debug("  propertyName="
                    + p.getName()
                    + ", value=" + p.getValue());
        }
    }
}
