package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.TestHelper
import spock.lang.Shared

class CheckoutCode extends TestHelper {
    @Shared projectName
    static final String agentHost  = System.getenv('EFAGENT_HOST')    ?: 'efagent-svn'

    def doSetupSpec() {
        createConfig()

        def result = createWrapperProject('CheckoutCode', ['CheckoutType', 'command', 'config', 'dest', 'FileName', 'IgnoreExternals', 'Revision_outpp', 'SubversionRevision', 'SubversionUrl'])
        assert result?.project
        projectName = result?.project.projectName
    }

    def 'checkout spec'() {
        when: 'Running simple checkout'
        def result = runProcedure(
            projectName,
            'CheckoutCode',
            [
                config          : configName,
                SubversionUrl   : "svn://${repoServer}/test_1",
                dest            : 'test_1',
                Revision_outpp  : "/myJob/test_1_revision",
                IgnoreExternals : IgnoreExternals
            ], [], agentHost, 3600
        )
        then: 'Procedure runs'
        assert result?.outcome == 'success'
        and: 'Revision looks like one'
        assert dsl("getProperty(propertyName: '/myJob/test_1_revision', jobId: '${result.jobId}')").property?.value =~ /^(\d+)(,\d+)*$/
        when:
        def workspace = dsl("getJobInfo(jobId: '${result.jobId}')").job?.workspace?.unix[0]
        assert workspace
        def files = mustExist + mustNotExist
        result = runProcedure(
            'ECSpec',
            'Files',
            [
                files   : files.join("\n"),
                action  : 'readable',
                basedir : workspace
            ], [], agentHost, 3600
        )
        then: 'Procedure runs'
        assert result?.outcome == 'success'
        and: 'Files that must exist do exist'
        mustExist.grep { dsl("getProperty(propertyName: '/myJob/result/${it}', jobId: '${result.jobId}')").property?.value == "1" }.size() == mustExist.size()
        and: 'Files that must not exist do not'
        mustNotExist.grep { dsl("getProperty(propertyName: '/myJob/result/${it}', jobId: '${result.jobId}')").property?.value == "0" }.size() == mustNotExist.size()

        where:
        IgnoreExternals | revisionRegex      | mustExist                                                                                                                             | mustNotExist
        0               | /^(\d+)(,\d+){3}$/ | [ 'test_1/test_commit', 'test_1/test_2/test_commit', 'test_1/test_3/test_commit', 'test_1/test_2/test_4/test_commit' ]                | []
        1               | /^(\d+)$/          | [ 'test_1/test_commit' ]                           | [ 'test_1/test_2/test_commit', 'test_1/test_3/test_commit', 'test_1/test_2/test_4/test_commit' ]
    }
}
