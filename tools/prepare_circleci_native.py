"""Generate an inert CircleCI UI-test candidate from the existing audited GH steps.

No network, CI API, checkout or build is performed. Activation is a separate step.
"""
import pathlib, yaml
ROOT=pathlib.Path(__file__).resolve().parents[1]
DEST=ROOT/'ci/circleci/native-ui.candidate.yml'
PYTHON_SETUP = {'run': {'name': 'Select Homebrew Python 3.12 for every native validation step',
         'command': 'export HOMEBREW_NO_AUTO_UPDATE=1\n'
                    'if ! brew list --versions python@3.12 >/dev/null 2>&1; then\n'
                    '  brew install python@3.12\n'
                    'fi\n'
                    'PYTHON_BIN="$(brew --prefix python@3.12)/libexec/bin"\n'
                    'test -x "$PYTHON_BIN/python3"\n'
                    'export PATH="$PYTHON_BIN:$PATH"\n'
                    'hash -r\n'
                    'printf \'export PATH=%q:$PATH\\n\' "$PYTHON_BIN" >> "$BASH_ENV"\n'
                    "python3 -c 'import platform,sys; print(sys.executable); print(sys.version); "
                    'assert sys.version_info >= (3,12); assert platform.machine() == "arm64"\'\n',
         'no_output_timeout': '10m'}}

def configuration():
    workflow=yaml.safe_load((ROOT/'.github/workflows/character-ui-smoke.yml').read_text())
    steps=['checkout', PYTHON_SETUP, {'run': {'name': 'Admit native UI runner without downloading resources',
        'command': 'python3 tools/native_ui_preflight.py | tee native-ui-preflight.json'}},
        {'run': {'name': 'Execute native Foundation policies without skipped checks',
         'command': 'python3 tools/native_policy_gate.py', 'no_output_timeout': '5m'}}]
    for step in workflow['jobs']['ui']['steps']:
        if 'run' in step:
            command=step['run'].replace("os.environ['GITHUB_ENV']", "os.environ['BASH_ENV']").replace("f.write('SIMULATOR_ID='", "f.write('export SIMULATOR_ID='")
            command=command.replace("<<'", "\\<<'")
            item={'name':step['name'],'command':command,'no_output_timeout':'20m'}
            if 'if' in step:item['when']='always'
            steps.append({'run':item})
        elif step.get('uses','').startswith('actions/upload-artifact'):
            for path in step['with']['path'].splitlines():steps.append({'store_artifacts':{'path':path}})
    steps.append({'store_artifacts':{'path':'native-ui-preflight.json'}})
    return {'version':2.1,'parameters':{'run-native':{'type':'boolean','default':False},
        'xcode-version':{'type':'string','default':'26.4.1'}},
        'jobs':{'native-ui':{'macos':{'xcode':'<< pipeline.parameters.xcode-version >>'},
            'shell':'/bin/bash -eo pipefail','steps':steps,'resource_class':'m4pro.medium'}},
        'workflows':{'native-validation':{'when':'<< pipeline.parameters.run-native >>','jobs':['native-ui']}}}
def main():
    DEST.write_text('# PRIVATE NONEXECUTING CANDIDATE. Not installed as .circleci/config.yml.\n'+yaml.safe_dump(configuration(),sort_keys=False))
    print(DEST)
if __name__=='__main__':main()
