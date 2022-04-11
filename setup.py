from setuptools import setup

setup(
    name='prprocessor',
    version='0.1.0',
    description='Handles GitHub PRs and syncing to Redmine and Jenkins',
    url='https://github.com/theforeman/prprocessor/tree/app',
    author='Ewoud Kohl van Wijngaarden',
    author_email='ewoud+python@kohlvanwijngaarden.nl',
    license='MIT',
    packages=['prprocessor'],
    install_requires=[
        'PyYAML',
        'octomachinery',
        'python-redmine',
    ],
    package_data={'prprocessor': ['config/*.yaml']},
    python_requires='>= 3.7',
)
