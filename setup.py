from setuptools import setup, find_packages

"""
https://click.palletsprojects.com/en/7.x/setuptools/#setuptools-integration
"""

install_requires = [
    'boto3',
    'click',
    'requests',
    'Jinja2',
    'jinja2-time'
]

setup(
    name='amify',
    version='0.1',
    description='Amify: Creates custom AMIs using Ansible for provisioning',
    url='https://github.com/crucialwebstudio/amify',
    author='Dan Bowen',
    license='Apache License 2.0',
    python_requires='>=3.6',
    install_requires=install_requires,
    entry_points={
        'console_scripts': 'amify = amify.__main__:cli'
    },
    packages=find_packages(),
    scripts=[],
    classifiers=[
        'Intended Audience :: Developers',
        'Intended Audience :: System Administrators',
        'License :: OSI Approved :: Apache Software License',
        'Natural Language :: English',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Topic :: Software Development',
        'Topic :: Software Development :: Libraries :: Python Modules',
    ],
    zip_safe=False
)
