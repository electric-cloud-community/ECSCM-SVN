package com.electriccloud.plugin.spec

import com.electriccloud.plugin.spec.TestHelper
import spock.lang.Shared

class getSCMTag extends TestHelper {
    @Shared projectName
    @Shared basedir
    @Shared checkoutProjectName
    @Shared revision

    def doSetupSpec() {
        createConfig()
        def result = createWrapperProject('getSCMTag', ['config', 'dest', 'repository', 'Revision_outpp', 'svnCheckExternals'])
        assert result?.project
        projectName = result?.project.projectName
    }

    def 'getscmtag'() {
        def result
        def prop
        when:
        result = runProcedure(
            projectName,
            'getSCMTag',
            [
                config           : configName,
                repository       : repository,
                dest             : "test_1",
                Revision_outpp   : "/myJob/revision",
                svnCheckExternals: svnCheckExternals
            ], [], null, 3600
        )
        then: 'Procedure runs'
        assert result?.outcome == 'success'
        when:
        prop = dsl("getProperty(propertyName: '/myJob/revision', jobId: '${result.jobId}')")
        revision = prop?.property?.value
        then:
        assert revision =~ revisionRegex
        where:
        repository                          | svnCheckExternals | revisionRegex
        "svn://${repoServer}/test_1"        | 0                 | /^\d+$/
        "svn://${repoServer}/test_1"        | 1                 | /^(\d+,){3}\d+$/
"""svn://${repoServer}/test_1
svn://${repoServer}/test_2
svn://${repoServer}/test_3
svn://${repoServer}/test_4
"""                                         | 0                 | /^(\d+,){3}\d+$/
"""svn://${repoServer}/test_1
svn://${repoServer}/test_2
svn://${repoServer}/test_3
svn://${repoServer}/test_4
"""                                         | 1                 | /^(\d+,){6}\d+$/

    }

}
